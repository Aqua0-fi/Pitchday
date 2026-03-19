// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { CCTPComposer, IMessageTransmitterV2 } from "../src/bridge/CCTPComposer.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { IERC20 } from "../src/interface/IERC20.sol";
import { Errors } from "../src/lib/Errors.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { AccountTestHelper } from "./utils/AccountTestHelper.sol";

// ============================================
// MOCKS
// ============================================

contract MockAqua is IAqua {
    mapping(address => mapping(address => mapping(bytes32 => mapping(address => uint256)))) public virtualBalances;
    mapping(address => mapping(address => mapping(bytes32 => uint8))) public tokensCounts;

    function ship(address app, bytes memory strategy, address[] memory tokens, uint256[] memory amounts)
        external
        override
        returns (bytes32 strategyHash)
    {
        strategyHash = keccak256(strategy);
        address maker = msg.sender;
        uint8 tokensCount = uint8(tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            virtualBalances[maker][app][strategyHash][tokens[i]] += amounts[i];
            tokensCounts[maker][app][strategyHash] = tokensCount;
        }
    }

    function dock(address app, bytes32 strategyHash, address[] memory tokens) external override {
        address maker = msg.sender;
        for (uint256 i = 0; i < tokens.length; i++) {
            virtualBalances[maker][app][strategyHash][tokens[i]] = 0;
            tokensCounts[maker][app][strategyHash] = 0xff;
        }
    }

    function rawBalances(address maker, address app, bytes32 strategyHash, address token)
        external
        view
        override
        returns (uint248 balance, uint8 tokensCount)
    {
        balance = uint248(virtualBalances[maker][app][strategyHash][token]);
        tokensCount = tokensCounts[maker][app][strategyHash];
    }

    function safeBalances(address, address, bytes32, address, address)
        external
        pure
        override
        returns (uint256, uint256)
    {
        return (0, 0);
    }
}

contract MockUSDC is IERC20 {
    string public name = "USDC";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

    contract MockMessageTransmitterV2 is IMessageTransmitterV2 {
        address public token;
        uint256 public mintAmount;

        constructor(address _token) {
            token = _token;
        }

        function setMintAmount(uint256 _amount) external {
            mintAmount = _amount;
        }

        function receiveMessage(bytes calldata, bytes calldata) external override returns (bool) {
            MockUSDC(token).mint(msg.sender, mintAmount);
            return true;
        }
    }

    // ============================================
    // END-TO-END CCTP DELIVERY TESTS
    // ============================================

    contract CCTPComposerDeliveryTest is Test {
        MockAqua public aqua;
        MockUSDC public usdc;
        MockMessageTransmitterV2 public transmitter;
        CCTPComposer public cctpComposer;
        BridgeRegistry public bridgeRegistry;
        LPAccount public account;
        LPAccount public accountImpl;
        UpgradeableBeacon public beacon;

        address public owner = address(this);
        address public factory = address(0xFACA);
        address public swapVMRouter = address(0x5555);

        uint256 constant AMOUNT = 1_000e6;
        bytes public strategyBytes = "cctp-delivery-strategy";
        bytes32 public strategyHash;

        /// @dev Build a mock CCTP message with hookData at offset 376
        ///      (144-byte outer header + 232-byte BurnMessageV2 fixed body)
        function _buildMockMessage(bytes memory hookData) internal pure returns (bytes memory) {
            bytes memory message = new bytes(376 + hookData.length);
            for (uint256 i = 0; i < hookData.length; i++) {
                message[376 + i] = hookData[i];
            }
            return message;
        }

        function setUp() public {
            aqua = new MockAqua();
            usdc = new MockUSDC();
            transmitter = new MockMessageTransmitterV2(address(usdc));

            // Deploy BridgeRegistry and CCTPComposer
            bridgeRegistry = new BridgeRegistry(owner);
            cctpComposer = new CCTPComposer(address(transmitter), address(usdc), owner);

            // Register CCTPComposer as trusted
            bridgeRegistry.addComposer(address(cctpComposer));

            // Deploy Account
            accountImpl = new LPAccount(address(bridgeRegistry));
            beacon = new UpgradeableBeacon(address(accountImpl), address(this));
            account = AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);

            strategyHash = keccak256(strategyBytes);
        }

        function test_e2e_cctp_relay_to_account() public {
            transmitter.setMintAmount(AMOUNT);

            address[] memory tokens = new address[](1);
            tokens[0] = address(usdc);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = AMOUNT;

            bytes memory composePayload = abi.encode(address(account), strategyBytes, tokens, amounts);

            // Relay and compose — should mint USDC → forward to account → ship in Aqua
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);

            // Verify tokens arrived at account
            assertEq(usdc.balanceOf(address(account)), AMOUNT);
            assertEq(usdc.balanceOf(address(cctpComposer)), 0);

            // Verify Aqua virtual balance
            (uint248 balance, uint8 tokensCount) =
                aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(usdc));
            assertEq(balance, AMOUNT);
            assertEq(tokensCount, 1);

            // Verify strategy tokens stored
            address[] memory storedTokens = account.getStrategyTokens(strategyHash);
            assertEq(storedTokens.length, 1);
            assertEq(storedTokens[0], address(usdc));
        }

        function test_e2e_cctp_relay_then_dock() public {
            transmitter.setMintAmount(AMOUNT);

            address[] memory tokens = new address[](1);
            tokens[0] = address(usdc);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = AMOUNT;

            bytes memory composePayload = abi.encode(address(account), strategyBytes, tokens, amounts);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);

            // Owner docks the strategy
            account.dock(strategyHash);

            (uint248 balance, uint8 tokensCount) =
                aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(usdc));
            assertEq(balance, 0);
            assertEq(tokensCount, 0xff); // docked

            // Tokens still in account
            assertEq(usdc.balanceOf(address(account)), AMOUNT);
        }

        function test_e2e_cctp_relay_partial_amounts() public {
            uint256 bridgeAmount = 500e6;
            transmitter.setMintAmount(bridgeAmount);

            address[] memory tokens = new address[](1);
            tokens[0] = address(usdc);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = bridgeAmount;

            bytes memory composePayload = abi.encode(address(account), strategyBytes, tokens, amounts);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);

            // Ship more
            transmitter.setMintAmount(bridgeAmount);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation2", composePayload);

            // Total should be 1000
            (uint248 balance,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(usdc));
            assertEq(balance, bridgeAmount * 2);
            assertEq(usdc.balanceOf(address(account)), bridgeAmount * 2);
        }

        function test_e2e_cctp_relay_multiple_accounts() public {
            LPAccount account2 =
                AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);

            transmitter.setMintAmount(AMOUNT);

            address[] memory tokens = new address[](1);
            tokens[0] = address(usdc);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = AMOUNT;

            // Relay to account 1
            bytes memory payload1 = abi.encode(address(account), strategyBytes, tokens, amounts);
            cctpComposer.relayAndCompose(_buildMockMessage(payload1), "att1", payload1);

            // Relay to account 2
            bytes memory payload2 = abi.encode(address(account2), strategyBytes, tokens, amounts);
            cctpComposer.relayAndCompose(_buildMockMessage(payload2), "att2", payload2);

            // Both accounts should have balances
            (uint248 bal1,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(usdc));
            (uint248 bal2,) = aqua.rawBalances(address(account2), swapVMRouter, strategyHash, address(usdc));
            assertEq(bal1, AMOUNT);
            assertEq(bal2, AMOUNT);
        }
    }
