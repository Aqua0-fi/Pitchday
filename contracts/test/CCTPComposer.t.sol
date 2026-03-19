// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CCTPComposer, IMessageTransmitterV2 } from "../src/bridge/CCTPComposer.sol";
import { IAccount } from "../src/interface/IAccount.sol";
import { IERC20 } from "../src/interface/IERC20.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";

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
        // Mint mock USDC to caller (CCTPComposer)
        MockUSDC(token).mint(msg.sender, mintAmount);
        return true;
    }
}

contract FailingMessageTransmitter is IMessageTransmitterV2 {
    function receiveMessage(bytes calldata, bytes calldata) external pure override returns (bool) {
        return false;
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

    contract MockAccount is IAccount {
        bytes public lastStrategyBytes;
        address[] public lastTokens;
        uint256[] public lastAmounts;
        bool public shouldRevert;

        function setShouldRevert(bool _val) external {
            shouldRevert = _val;
        }

        function onCrosschainDeposit(bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts)
            external
            override
            returns (bytes32)
        {
            if (shouldRevert) revert("aqua ship failed");
            lastStrategyBytes = strategyBytes;
            lastTokens = tokens;
            lastAmounts = amounts;
            return keccak256(strategyBytes);
        }

        function bridgeStargate(uint32, address, bytes calldata, address, uint256, uint256, uint128, uint128)
            external
            payable
            override
            returns (bytes32)
        {
            return bytes32(0);
        }

        function bridgeCCTP(uint32, address, bytes calldata, address, uint256, uint256, uint32)
            external
            payable
            override
            returns (uint64)
        {
            return 0;
        }
    }

    contract CCTPComposerTest is Test {
        CCTPComposer public cctpComposer;
        MockMessageTransmitterV2 public transmitter;
        MockUSDC public usdc;
        MockAccount public mockAccount;

        address public owner = address(this);
        address public other = address(0xBEEF);
        uint256 public amount = 1_000e6;

        bytes public strategyBytes = "strategy";
        address[] public tokens;
        uint256[] public composeAmounts;

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
            usdc = new MockUSDC();
            transmitter = new MockMessageTransmitterV2(address(usdc));
            transmitter.setMintAmount(amount);
            mockAccount = new MockAccount();
            cctpComposer = new CCTPComposer(address(transmitter), address(usdc), owner);

            tokens = new address[](1);
            tokens[0] = address(usdc);
            composeAmounts = new uint256[](1);
            composeAmounts[0] = amount;
        }

        // ============================================
        // CONSTRUCTOR TESTS
        // ============================================

        function test_constructor_sets_state() public view {
            assertEq(cctpComposer.MESSAGE_TRANSMITTER(), address(transmitter));
            assertEq(cctpComposer.TOKEN(), address(usdc));
            assertEq(cctpComposer.owner(), owner);
        }

        function test_constructor_reverts_zero_transmitter() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            new CCTPComposer(address(0), address(usdc), owner);
        }

        function test_constructor_reverts_zero_token() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            new CCTPComposer(address(transmitter), address(0), owner);
        }

        // ============================================
        // RELAY AND COMPOSE TESTS
        // ============================================

        function test_relayAndCompose_full_flow() public {
            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, composeAmounts);

            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);

            // Verify tokens were forwarded to account
            assertEq(usdc.balanceOf(address(mockAccount)), amount);
            assertEq(usdc.balanceOf(address(cctpComposer)), 0);

            // Verify onCrosschainDeposit was called
            assertEq(keccak256(mockAccount.lastStrategyBytes()), keccak256(strategyBytes));
            assertEq(mockAccount.lastTokens(0), address(usdc));
            assertEq(mockAccount.lastAmounts(0), amount);
        }

        function test_relayAndCompose_emits_event() public {
            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, composeAmounts);

            vm.expectEmit(false, true, false, true);
            emit Events.CCTPComposeReceived(amount, keccak256(strategyBytes));
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_on_relay_failure() public {
            FailingMessageTransmitter failingTransmitter = new FailingMessageTransmitter();
            CCTPComposer failComposer = new CCTPComposer(address(failingTransmitter), address(usdc), owner);

            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, composeAmounts);

            vm.expectRevert(Errors.CCTPRelayFailed.selector);
            failComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_zero_amount() public {
            transmitter.setMintAmount(0);

            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, composeAmounts);

            vm.expectRevert(Errors.ZeroAmount.selector);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_empty_payload() public {
            vm.expectRevert(); // hookData mismatch or abi.decode will revert
            cctpComposer.relayAndCompose(_buildMockMessage(""), "attestation", "");
        }

        function test_relayAndCompose_reverts_zero_account() public {
            bytes memory composePayload = abi.encode(address(0), strategyBytes, tokens, composeAmounts);

            vm.expectRevert(Errors.ZeroAddress.selector);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_empty_strategy() public {
            bytes memory composePayload = abi.encode(address(mockAccount), "", tokens, composeAmounts);

            vm.expectRevert(Errors.InvalidStrategyBytes.selector);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_empty_tokens() public {
            address[] memory emptyTokens = new address[](0);
            uint256[] memory emptyAmounts = new uint256[](0);
            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, emptyTokens, emptyAmounts);

            vm.expectRevert(Errors.InvalidInput.selector);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_mismatched_arrays() public {
            uint256[] memory wrongAmounts = new uint256[](2);
            wrongAmounts[0] = amount;
            wrongAmounts[1] = amount;
            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, wrongAmounts);

            vm.expectRevert(Errors.InvalidInput.selector);
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_on_account_failure() public {
            mockAccount.setShouldRevert(true);

            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, composeAmounts);

            vm.expectRevert("aqua ship failed");
            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
        }

        // ============================================
        // SETTER TESTS
        // ============================================

        function test_setMessageTransmitter_updates() public {
            address newTransmitter = address(0x9999);
            cctpComposer.setMessageTransmitter(newTransmitter);
            assertEq(cctpComposer.MESSAGE_TRANSMITTER(), newTransmitter);
        }

        function test_setMessageTransmitter_reverts_zero() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            cctpComposer.setMessageTransmitter(address(0));
        }

        function test_setMessageTransmitter_reverts_not_owner() public {
            vm.prank(other);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
            cctpComposer.setMessageTransmitter(address(0x9999));
        }

        function test_setMessageTransmitter_emits_event() public {
            address newTransmitter = address(0x9999);
            vm.expectEmit(true, true, false, false);
            emit Events.MessageTransmitterSet(address(transmitter), newTransmitter);
            cctpComposer.setMessageTransmitter(newTransmitter);
        }

        function test_setToken_updates() public {
            address newToken = address(0x8888);
            cctpComposer.setToken(newToken);
            assertEq(cctpComposer.TOKEN(), newToken);
        }

        function test_setToken_reverts_zero() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            cctpComposer.setToken(address(0));
        }

        function test_setToken_reverts_not_owner() public {
            vm.prank(other);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
            cctpComposer.setToken(address(0x8888));
        }

        function test_setToken_emits_event() public {
            address newToken = address(0x8888);
            vm.expectEmit(true, true, false, false);
            emit Events.CCTPComposerTokenSet(address(usdc), newToken);
            cctpComposer.setToken(newToken);
        }

        // ============================================
        // FUZZ TESTS
        // ============================================

        function testFuzz_relayAndCompose_amount(uint256 _amount) public {
            _amount = bound(_amount, 1, type(uint128).max);
            transmitter.setMintAmount(_amount);

            uint256[] memory fuzzAmounts = new uint256[](1);
            fuzzAmounts[0] = _amount;
            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, fuzzAmounts);

            cctpComposer.relayAndCompose(_buildMockMessage(composePayload), "attestation", composePayload);
            assertEq(usdc.balanceOf(address(mockAccount)), _amount);
        }

        // ============================================
        // HOOK DATA VERIFICATION TESTS
        // ============================================

        function test_relayAndCompose_reverts_hookData_mismatch() public {
            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, composeAmounts);
            bytes memory differentPayload = abi.encode(address(0xDEAD), strategyBytes, tokens, composeAmounts);

            vm.expectRevert(Errors.HookDataMismatch.selector);
            cctpComposer.relayAndCompose(_buildMockMessage(differentPayload), "attestation", composePayload);
        }

        function test_relayAndCompose_reverts_message_too_short() public {
            bytes memory composePayload = abi.encode(address(mockAccount), strategyBytes, tokens, composeAmounts);
            bytes memory shortMessage = new bytes(375); // less than 376

            vm.expectRevert(Errors.CCTPMessageTooShort.selector);
            cctpComposer.relayAndCompose(shortMessage, "attestation", composePayload);
        }
    }
