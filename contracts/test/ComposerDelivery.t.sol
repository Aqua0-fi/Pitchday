// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Composer } from "../src/bridge/Composer.sol";
import { IAccount } from "../src/interface/IAccount.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {
    EndpointV2Mock as EndpointV2
} from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";

/// @title ComposerDeliveryTest
/// @notice Tests Composer's lzCompose delivery through the real LZ EndpointV2Mock compose pipeline.
/// @dev Follows LayerZero V2 testing guidelines:
///      1. Deploy EndpointV2Mock as the LZ endpoint
///      2. Stargate (simulated) calls endpoint.sendCompose() to queue the compose message
///      3. Executor (simulated) calls endpoint.lzCompose() to deliver through the compose queue
///      4. Endpoint verifies the message hash, then calls Composer.lzCompose()
///      This ensures our Composer works correctly with the real LZ compose pipeline (hash verification,
///      reentrancy protection, ComposeDelivered events) — not just a raw vm.prank() bypass.

// Minimal ERC20 mock
contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(balanceOf[from] >= amount, "Insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Mock Account that records calls
contract MockAccount is IAccount {
    bool public called;
    bytes public lastStrategyBytes;
    address[] public lastTokens;
    uint256[] public lastAmounts;

    function onCrosschainDeposit(bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts)
        external
        override
        returns (bytes32)
    {
        called = true;
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

contract ComposerDeliveryTest is Test {
    MockToken public token;
    EndpointV2 public endpoint;
    Composer public composer;
    MockAccount public mockAccount;

    address public owner = address(this);
    address public stargate = address(0x574747);
    address public executor = address(0xE1EC);

    uint32 constant LOCAL_EID = 30184; // Base
    uint64 constant NONCE = 1;
    uint32 constant SRC_EID = 30320; // Unichain
    address constant COMPOSE_FROM = address(0xABCD);

    function setUp() public {
        // Deploy the real LZ EndpointV2Mock
        endpoint = new EndpointV2(LOCAL_EID, owner);

        // Deploy our contracts
        token = new MockToken();
        composer = new Composer(address(endpoint), owner);
        composer.registerPool(stargate, address(token));
        mockAccount = new MockAccount();

        // Fund composer with tokens (simulates Stargate having already delivered bridged tokens)
        token.mint(address(composer), 1000 ether);
    }

    // ============================================
    // HELPERS
    // ============================================

    /// @dev Build the OFT compose message in the format OFTComposeMsgCodec expects
    function _buildOFTComposeMsg(uint256 amountLD, bytes memory appComposeMsg) internal pure returns (bytes memory) {
        return OFTComposeMsgCodec.encode(
            NONCE, SRC_EID, amountLD, abi.encodePacked(bytes32(uint256(uint160(COMPOSE_FROM))), appComposeMsg)
        );
    }

    /// @dev Build the app-level compose payload: (account, strategyBytes, tokens, amounts)
    function _buildAppPayload(address account, uint256 amount) internal pure returns (bytes memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        return abi.encode(account, bytes("test-strategy"), tokens, amounts);
    }

    /// @dev Simulate Stargate calling endpoint.sendCompose() to queue a compose for our Composer
    function _queueCompose(bytes32 guid, bytes memory composeMsg) internal {
        vm.prank(stargate);
        endpoint.sendCompose(address(composer), guid, 0, composeMsg);
    }

    /// @dev Simulate an executor calling endpoint.lzCompose() to deliver the queued compose
    function _deliverCompose(bytes32 guid, bytes memory composeMsg) internal {
        vm.prank(executor);
        endpoint.lzCompose(stargate, address(composer), guid, 0, composeMsg, "");
    }

    // ============================================
    // HAPPY PATH: Full compose delivery through endpoint
    // ============================================

    function test_delivery_full_compose_pipeline() public {
        bytes32 guid = bytes32(uint256(42));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 1000 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(1000 ether, appPayload);

        // Step 1: Stargate queues compose on endpoint (simulates what happens after lzReceive)
        _queueCompose(guid, composeMsg);

        // Verify compose is queued (hash stored)
        bytes32 queuedHash = endpoint.composeQueue(stargate, address(composer), guid, 0);
        assertEq(queuedHash, keccak256(composeMsg), "compose should be queued");

        // Step 2: Executor delivers compose through endpoint → Composer.lzCompose()
        _deliverCompose(guid, composeMsg);

        // Verify Composer processed correctly
        assertEq(token.balanceOf(address(composer)), 0, "composer should have forwarded all tokens");
        assertEq(token.balanceOf(address(mockAccount)), 1000 ether, "account should have received tokens");
        assertTrue(mockAccount.called(), "account.onCrosschainDeposit should have been called");
        assertEq(
            keccak256(mockAccount.lastStrategyBytes()), keccak256(bytes("test-strategy")), "strategy bytes should match"
        );

        // Verify compose was marked as delivered on endpoint
        bytes32 deliveredHash = endpoint.composeQueue(stargate, address(composer), guid, 0);
        assertEq(deliveredHash, bytes32(uint256(1)), "compose should be marked as delivered");
    }

    function test_delivery_emits_ComposeReceived() public {
        bytes32 guid = bytes32(uint256(99));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 500 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(500 ether, appPayload);

        _queueCompose(guid, composeMsg);

        vm.expectEmit(true, true, false, true);
        emit Events.ComposeReceived(guid, stargate, 500 ether, keccak256(bytes("test-strategy")));

        _deliverCompose(guid, composeMsg);
    }

    function test_delivery_endpoint_emits_ComposeDelivered() public {
        bytes32 guid = bytes32(uint256(77));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 100 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(100 ether, appPayload);

        _queueCompose(guid, composeMsg);

        // The endpoint itself emits ComposeDelivered
        vm.expectEmit(true, true, false, true, address(endpoint));
        emit ComposeDelivered(stargate, address(composer), guid, 0);

        _deliverCompose(guid, composeMsg);
    }

    // ============================================
    // ENDPOINT COMPOSE QUEUE SECURITY
    // ============================================

    function test_delivery_rejects_tampered_message() public {
        bytes32 guid = bytes32(uint256(1));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 1000 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(1000 ether, appPayload);

        // Queue the original message
        _queueCompose(guid, composeMsg);

        // Try to deliver a tampered message (different amount)
        bytes memory tamperedPayload = _buildAppPayload(address(mockAccount), 9999 ether);
        bytes memory tamperedMsg = _buildOFTComposeMsg(9999 ether, tamperedPayload);

        vm.prank(executor);
        vm.expectRevert(); // LZ_ComposeNotFound — hash mismatch
        endpoint.lzCompose(stargate, address(composer), guid, 0, tamperedMsg, "");
    }

    function test_delivery_rejects_replay() public {
        bytes32 guid = bytes32(uint256(1));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 100 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(100 ether, appPayload);

        // Queue and deliver
        _queueCompose(guid, composeMsg);
        _deliverCompose(guid, composeMsg);

        // Try to replay the same compose — endpoint rejects
        token.mint(address(composer), 100 ether);
        vm.prank(executor);
        vm.expectRevert(); // LZ_ComposeNotFound — already marked as RECEIVED
        endpoint.lzCompose(stargate, address(composer), guid, 0, composeMsg, "");
    }

    function test_delivery_rejects_unqueued_compose() public {
        bytes32 guid = bytes32(uint256(1));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 100 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(100 ether, appPayload);

        // Try to deliver without queueing first
        vm.prank(executor);
        vm.expectRevert(); // LZ_ComposeNotFound — nothing in queue
        endpoint.lzCompose(stargate, address(composer), guid, 0, composeMsg, "");
    }

    function test_delivery_rejects_wrong_from() public {
        bytes32 guid = bytes32(uint256(1));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 100 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(100 ether, appPayload);

        // Queue from stargate
        _queueCompose(guid, composeMsg);

        // Try to deliver claiming a different _from — endpoint hash lookup fails
        vm.prank(executor);
        vm.expectRevert(); // LZ_ComposeNotFound — wrong _from key
        endpoint.lzCompose(address(0xBAD), address(composer), guid, 0, composeMsg, "");
    }

    // ============================================
    // COMPOSER VALIDATION (via endpoint delivery)
    // ============================================

    function test_delivery_reverts_zero_amount() public {
        bytes32 guid = bytes32(uint256(1));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 0);
        bytes memory composeMsg = _buildOFTComposeMsg(0, appPayload);

        _queueCompose(guid, composeMsg);

        vm.prank(executor);
        vm.expectRevert(); // Composer reverts with ZeroAmount, endpoint bubbles it up
        endpoint.lzCompose(stargate, address(composer), guid, 0, composeMsg, "");
    }

    function test_delivery_reverts_zero_account() public {
        bytes32 guid = bytes32(uint256(1));
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;
        bytes memory appPayload = abi.encode(address(0), bytes("strategy"), tokens, amounts);
        bytes memory composeMsg = _buildOFTComposeMsg(100 ether, appPayload);

        _queueCompose(guid, composeMsg);

        vm.prank(executor);
        vm.expectRevert(); // Composer reverts with ZeroAddress
        endpoint.lzCompose(stargate, address(composer), guid, 0, composeMsg, "");
    }

    // ============================================
    // MULTIPLE COMPOSES (different GUIDs)
    // ============================================

    function test_delivery_multiple_sequential_composes() public {
        // Compose 1
        bytes32 guid1 = bytes32(uint256(1));
        bytes memory payload1 = _buildAppPayload(address(mockAccount), 300 ether);
        bytes memory msg1 = _buildOFTComposeMsg(300 ether, payload1);

        _queueCompose(guid1, msg1);
        _deliverCompose(guid1, msg1);

        assertEq(token.balanceOf(address(mockAccount)), 300 ether, "first compose should deliver 300");

        // Compose 2 (new GUID, new account)
        MockAccount account2 = new MockAccount();
        bytes32 guid2 = bytes32(uint256(2));
        bytes memory payload2 = _buildAppPayload(address(account2), 200 ether);
        bytes memory msg2 = _buildOFTComposeMsg(200 ether, payload2);

        _queueCompose(guid2, msg2);
        _deliverCompose(guid2, msg2);

        assertEq(token.balanceOf(address(account2)), 200 ether, "second compose should deliver 200");
        assertEq(token.balanceOf(address(composer)), 500 ether, "composer should have 500 remaining");
    }

    // ============================================
    // FUZZ: Delivery with variable amounts
    // ============================================

    function testFuzz_delivery_amount(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint128).max);
        token.mint(address(composer), _amount); // ensure enough balance

        bytes32 guid = bytes32(uint256(1));
        bytes memory appPayload = _buildAppPayload(address(mockAccount), _amount);
        bytes memory composeMsg = _buildOFTComposeMsg(_amount, appPayload);

        _queueCompose(guid, composeMsg);
        _deliverCompose(guid, composeMsg);

        assertEq(token.balanceOf(address(mockAccount)), _amount, "account should receive exact amount");
        assertTrue(mockAccount.called(), "onCrosschainDeposit should be called");
    }

    function testFuzz_delivery_guid(bytes32 _guid) public {
        bytes memory appPayload = _buildAppPayload(address(mockAccount), 100 ether);
        bytes memory composeMsg = _buildOFTComposeMsg(100 ether, appPayload);

        _queueCompose(_guid, composeMsg);
        _deliverCompose(_guid, composeMsg);

        assertTrue(mockAccount.called(), "should work with any GUID");
    }

    // ============================================
    // EVENT FROM ENDPOINT
    // ============================================

    event ComposeDelivered(address from, address to, bytes32 guid, uint16 index);

    receive() external payable { }
}
