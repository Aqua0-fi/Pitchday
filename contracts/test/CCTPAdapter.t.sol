// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CCTPAdapter, ITokenMessengerV2 } from "../src/bridge/CCTPAdapter.sol";
import { IERC20 } from "../src/interface/IERC20.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";

contract MockTokenMessengerV2 is ITokenMessengerV2 {
    uint64 public nonceCounter;
    uint256 public lastAmount;
    uint32 public lastDstDomain;
    bytes32 public lastMintRecipient;
    address public lastBurnToken;
    bytes32 public lastDestinationCaller;
    bytes public lastHookData;

    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256,
        uint32,
        bytes calldata hookData
    ) external override returns (uint64 nonce) {
        nonceCounter++;
        lastAmount = amount;
        lastDstDomain = destinationDomain;
        lastMintRecipient = mintRecipient;
        lastBurnToken = burnToken;
        lastDestinationCaller = destinationCaller;
        lastHookData = hookData;
        return nonceCounter;
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

    contract CCTPAdapterTest is Test {
        CCTPAdapter public adapter;
        MockTokenMessengerV2 public messenger;
        MockUSDC public usdc;

        address public owner = address(this);
        address public other = address(0xBEEF);
        address public recipient = address(0xCAFE);
        uint256 public amount = 1_000e6; // 1000 USDC

        function setUp() public {
            messenger = new MockTokenMessengerV2();
            usdc = new MockUSDC();
            adapter = new CCTPAdapter(address(messenger), owner);
        }

        // ============================================
        // CONSTRUCTOR TESTS
        // ============================================

        function test_constructor_sets_state() public view {
            assertEq(adapter.TOKEN_MESSENGER(), address(messenger));
            assertEq(adapter.owner(), owner);
        }

        function test_constructor_reverts_zero_messenger() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            new CCTPAdapter(address(0), owner);
        }

        // ============================================
        // BRIDGE WITH HOOK TESTS
        // ============================================

        function test_bridgeWithHook_pulls_tokens_and_calls_messenger() public {
            usdc.mint(address(this), amount);
            usdc.approve(address(adapter), amount);

            bytes memory hookData = abi.encode(address(0xDEAD), "strategy");
            uint64 nonce = adapter.bridgeWithHook(address(usdc), amount, 10, recipient, hookData, 0, 1000);

            assertEq(nonce, 1);
            assertEq(messenger.lastAmount(), amount);
            assertEq(messenger.lastDstDomain(), 10);
            assertEq(messenger.lastMintRecipient(), bytes32(uint256(uint160(recipient))));
            assertEq(messenger.lastBurnToken(), address(usdc));
            assertEq(messenger.lastDestinationCaller(), bytes32(uint256(uint160(recipient))));
            assertEq(keccak256(messenger.lastHookData()), keccak256(hookData));
        }

        function test_bridgeWithHook_sets_destinationCaller_to_recipient() public {
            usdc.mint(address(this), amount);
            usdc.approve(address(adapter), amount);

            adapter.bridgeWithHook(address(usdc), amount, 10, recipient, "", 0, 1000);
            assertEq(messenger.lastDestinationCaller(), bytes32(uint256(uint160(recipient))));
        }

        function test_bridgeWithHook_reverts_zero_amount() public {
            vm.expectRevert(Errors.ZeroAmount.selector);
            adapter.bridgeWithHook(address(usdc), 0, 10, recipient, "", 0, 1000);
        }

        function test_bridgeWithHook_reverts_zero_token() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            adapter.bridgeWithHook(address(0), amount, 10, recipient, "", 0, 1000);
        }

        function test_bridgeWithHook_reverts_zero_recipient() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            adapter.bridgeWithHook(address(usdc), amount, 10, address(0), "", 0, 1000);
        }

        function test_bridgeWithHook_emits_event() public {
            usdc.mint(address(this), amount);
            usdc.approve(address(adapter), amount);

            vm.expectEmit(true, true, false, true);
            emit Events.CCTPBridged(10, recipient, address(usdc), amount, 1);
            adapter.bridgeWithHook(address(usdc), amount, 10, recipient, "", 0, 1000);
        }

        function test_bridgeWithHook_increments_nonce() public {
            usdc.mint(address(this), amount * 3);
            usdc.approve(address(adapter), amount * 3);

            uint64 nonce1 = adapter.bridgeWithHook(address(usdc), amount, 10, recipient, "", 0, 1000);
            uint64 nonce2 = adapter.bridgeWithHook(address(usdc), amount, 10, recipient, "", 0, 1000);
            uint64 nonce3 = adapter.bridgeWithHook(address(usdc), amount, 10, recipient, "", 0, 1000);

            assertEq(nonce1, 1);
            assertEq(nonce2, 2);
            assertEq(nonce3, 3);
        }

        // ============================================
        // SET TOKEN MESSENGER TESTS
        // ============================================

        function test_setTokenMessenger_updates_address() public {
            address newMessenger = address(0x9999);
            adapter.setTokenMessenger(newMessenger);
            assertEq(adapter.TOKEN_MESSENGER(), newMessenger);
        }

        function test_setTokenMessenger_reverts_zero_address() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            adapter.setTokenMessenger(address(0));
        }

        function test_setTokenMessenger_reverts_not_owner() public {
            vm.prank(other);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
            adapter.setTokenMessenger(address(0x9999));
        }

        function test_setTokenMessenger_emits_event() public {
            address newMessenger = address(0x9999);
            vm.expectEmit(true, true, false, false);
            emit Events.TokenMessengerSet(address(messenger), newMessenger);
            adapter.setTokenMessenger(newMessenger);
        }

        // ============================================
        // FUZZ TESTS
        // ============================================

        function testFuzz_bridgeWithHook_amount(uint256 _amount) public {
            _amount = bound(_amount, 1, type(uint128).max);
            usdc.mint(address(this), _amount);
            usdc.approve(address(adapter), _amount);

            uint64 nonce = adapter.bridgeWithHook(address(usdc), _amount, 10, recipient, "", 0, 1000);
            assertEq(nonce, 1);
            assertEq(messenger.lastAmount(), _amount);
        }
    }
