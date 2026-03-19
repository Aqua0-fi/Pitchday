// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { Rebalancer } from "../src/rebalancer/Rebalancer.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";
import { RebalanceStatus } from "../src/lib/Types.sol";
import { AccountTestHelper } from "./utils/AccountTestHelper.sol";

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

    function safeBalances(address maker, address app, bytes32 strategyHash, address token0, address token1)
        external
        view
        override
        returns (uint256 balance0, uint256 balance1)
    {
        balance0 = virtualBalances[maker][app][strategyHash][token0];
        balance1 = virtualBalances[maker][app][strategyHash][token1];
    }
}

contract RebalancerTest is Test {
    MockAqua public aqua;
    LPAccount public account;
    LPAccount public accountImpl;
    UpgradeableBeacon public beacon;
    Rebalancer public rebalancer;
    Rebalancer public rebalancerImpl;
    BridgeRegistry public bridgeRegistry;

    address public ownerAddr = address(this);
    address public factory = address(0xFACA);
    address public other = address(0xBEEF);
    address public tokenAddr = address(0xCAFE);
    address public swapVMRouter = address(0x5555);

    bytes public strategyBytes = "strategy";
    bytes32 public strategyHash;
    uint256 public amount = 1_000 ether;
    uint32 public srcChain = 8453; // Base
    uint32 public dstChain = 42161; // Arbitrum

    address[] public tokens;
    uint256[] public amounts;

    function setUp() public {
        aqua = new MockAqua();
        bridgeRegistry = new BridgeRegistry(address(this));

        // Deploy Account via BeaconProxy
        accountImpl = new LPAccount(address(bridgeRegistry));
        beacon = new UpgradeableBeacon(address(accountImpl), address(this));
        account = AccountTestHelper.deployAccountProxy(address(beacon), ownerAddr, factory, address(aqua), swapVMRouter);

        // Deploy Rebalancer behind ERC1967Proxy
        rebalancerImpl = new Rebalancer();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(rebalancerImpl), abi.encodeCall(Rebalancer.initialize, (ownerAddr)));
        rebalancer = Rebalancer(address(proxy));

        strategyHash = keccak256(strategyBytes);

        tokens = new address[](1);
        tokens[0] = tokenAddr;
        amounts = new uint256[](1);
        amounts[0] = amount;
    }

    // ============================================
    // INITIALIZATION TESTS
    // ============================================

    function test_initialize_sets_owner_and_rebalancer() public view {
        assertEq(rebalancer.owner(), ownerAddr);
        assertEq(rebalancer.rebalancer(), ownerAddr);
    }

    function test_initialize_reverts_when_called_twice() public {
        vm.expectRevert();
        rebalancer.initialize(ownerAddr);
    }

    // ============================================
    // UPGRADE TESTS
    // ============================================

    function test_upgrade_preserves_state() public {
        // Create an operation
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        assertTrue(rebalancer.operationExists(operationId));

        // Upgrade
        Rebalancer newImpl = new Rebalancer();
        rebalancer.upgradeToAndCall(address(newImpl), "");

        // State should be preserved
        assertTrue(rebalancer.operationExists(operationId));
        assertEq(rebalancer.owner(), ownerAddr);
        assertEq(rebalancer.rebalancer(), ownerAddr);
    }

    function test_upgrade_reverts_not_owner() public {
        Rebalancer newImpl = new Rebalancer();
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        rebalancer.upgradeToAndCall(address(newImpl), "");
    }

    // ============================================
    // EXISTING TESTS (adapted for proxy)
    // ============================================

    function test_triggerRebalance_reverts_zero_lpAccount() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        rebalancer.triggerRebalance(address(0), srcChain, dstChain, tokenAddr, amount);
    }

    function test_triggerRebalance_reverts_zero_token() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        rebalancer.triggerRebalance(address(account), srcChain, dstChain, address(0), amount);
    }

    function test_triggerRebalance_reverts_zero_amount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, 0);
    }

    function test_triggerRebalance_reverts_same_chain() public {
        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.triggerRebalance(address(account), srcChain, srcChain, tokenAddr, amount);
    }

    function test_triggerRebalance_reverts_not_authorized() public {
        vm.expectRevert(Errors.NotAuthorized.selector);
        rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
    }

    function test_triggerRebalance_records_operation() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);

        assertTrue(rebalancer.operationExists(operationId));

        (
            address lpAccount,
            uint32 opSrcChainId,
            uint32 opDstChainId,
            address opToken,
            uint256 opAmount,
            bytes32 messageGuid,
            RebalanceStatus status,
            uint256 initiatedAt,
            uint256 completedAt
        ) = rebalancer.operations(operationId);

        assertEq(lpAccount, address(account));
        assertEq(opSrcChainId, srcChain);
        assertEq(opDstChainId, dstChain);
        assertEq(opToken, tokenAddr);
        assertEq(opAmount, amount);
        assertEq(messageGuid, bytes32(0));
        assertEq(uint256(status), uint256(RebalanceStatus.PENDING));
        assertGt(initiatedAt, 0);
        assertEq(completedAt, 0);
    }

    function test_executeDock_docks_strategy() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);

        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);

        rebalancer.executeDock(operationId, strategyHash);

        (,,,,,, RebalanceStatus status,,) = rebalancer.operations(operationId);
        assertEq(uint256(status), uint256(RebalanceStatus.DOCKED));
    }

    function test_executeDock_reverts_not_pending() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);

        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);

        rebalancer.executeDock(operationId, strategyHash);

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.executeDock(operationId, strategyHash);
    }

    function test_recordBridging_sets_guid() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);

        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);

        rebalancer.executeDock(operationId, strategyHash);

        bytes32 guid = keccak256("test-guid");
        rebalancer.recordBridging(operationId, guid);

        (,,,,, bytes32 messageGuid, RebalanceStatus status,,) = rebalancer.operations(operationId);
        assertEq(messageGuid, guid);
        assertEq(uint256(status), uint256(RebalanceStatus.BRIDGING));
    }

    function test_confirmRebalance_completes() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);

        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);

        rebalancer.executeDock(operationId, strategyHash);
        rebalancer.recordBridging(operationId, keccak256("test-guid"));
        rebalancer.confirmRebalance(operationId);

        (,,,,,, RebalanceStatus status,, uint256 completedAt) = rebalancer.operations(operationId);
        assertEq(uint256(status), uint256(RebalanceStatus.COMPLETED));
        assertGt(completedAt, 0);
    }

    function test_confirmRebalance_reverts_not_bridging() public {
        account.authorizeRebalancer(address(rebalancer));

        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.confirmRebalance(operationId);
    }

    function test_failRebalance_sets_failed() public {
        account.authorizeRebalancer(address(rebalancer));

        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);

        rebalancer.failRebalance(operationId, "bridge failed");

        (,,,,,, RebalanceStatus status,, uint256 completedAt) = rebalancer.operations(operationId);
        assertEq(uint256(status), uint256(RebalanceStatus.FAILED));
        assertGt(completedAt, 0);
    }

    function test_setRebalancer_only_owner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        rebalancer.setRebalancer(other);
    }

    function test_transferOwnership() public {
        rebalancer.transferOwnership(other);

        vm.prank(other);
        rebalancer.setRebalancer(other);
        assertEq(rebalancer.rebalancer(), other);
    }

    function test_operations_reverts_not_found() public {
        vm.expectRevert(Errors.RebalanceOperationNotFound.selector);
        rebalancer.getOperation(bytes32(0));
    }

    // ============================================
    // ACCESS CONTROL (NotRebalancer)
    // ============================================

    function test_triggerRebalance_reverts_not_rebalancer() public {
        account.authorizeRebalancer(address(rebalancer));
        vm.prank(other);
        vm.expectRevert(Errors.NotRebalancer.selector);
        rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
    }

    function test_executeDock_reverts_not_rebalancer() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        vm.prank(other);
        vm.expectRevert(Errors.NotRebalancer.selector);
        rebalancer.executeDock(operationId, strategyHash);
    }

    function test_recordBridging_reverts_not_rebalancer() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        vm.prank(other);
        vm.expectRevert(Errors.NotRebalancer.selector);
        rebalancer.recordBridging(operationId, keccak256("guid"));
    }

    function test_confirmRebalance_reverts_not_rebalancer() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        rebalancer.recordBridging(operationId, keccak256("guid"));
        vm.prank(other);
        vm.expectRevert(Errors.NotRebalancer.selector);
        rebalancer.confirmRebalance(operationId);
    }

    function test_failRebalance_reverts_not_rebalancer() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        vm.prank(other);
        vm.expectRevert(Errors.NotRebalancer.selector);
        rebalancer.failRebalance(operationId, "reason");
    }

    // ============================================
    // OPERATION NOT FOUND
    // ============================================

    function test_executeDock_reverts_not_found() public {
        vm.expectRevert(Errors.RebalanceOperationNotFound.selector);
        rebalancer.executeDock(bytes32(uint256(999)), strategyHash);
    }

    function test_recordBridging_reverts_not_found() public {
        vm.expectRevert(Errors.RebalanceOperationNotFound.selector);
        rebalancer.recordBridging(bytes32(uint256(999)), keccak256("guid"));
    }

    function test_confirmRebalance_reverts_not_found() public {
        vm.expectRevert(Errors.RebalanceOperationNotFound.selector);
        rebalancer.confirmRebalance(bytes32(uint256(999)));
    }

    function test_failRebalance_reverts_not_found() public {
        vm.expectRevert(Errors.RebalanceOperationNotFound.selector);
        rebalancer.failRebalance(bytes32(uint256(999)), "reason");
    }

    // ============================================
    // STATE MACHINE
    // ============================================

    function test_recordBridging_reverts_not_docked() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.recordBridging(operationId, keccak256("guid"));
    }

    function test_failRebalance_reverts_already_completed() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        rebalancer.recordBridging(operationId, keccak256("guid"));
        rebalancer.confirmRebalance(operationId);
        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.failRebalance(operationId, "too late");
    }

    function test_failRebalance_reverts_already_failed() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.failRebalance(operationId, "first fail");
        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.failRebalance(operationId, "second fail");
    }

    // ============================================
    // TERMINAL STATE TRANSITIONS
    // ============================================

    function test_executeDock_reverts_from_completed() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        rebalancer.recordBridging(operationId, keccak256("guid"));
        rebalancer.confirmRebalance(operationId);

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.executeDock(operationId, strategyHash);
    }

    function test_recordBridging_reverts_from_completed() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        rebalancer.recordBridging(operationId, keccak256("guid"));
        rebalancer.confirmRebalance(operationId);

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.recordBridging(operationId, keccak256("guid-2"));
    }

    function test_confirmRebalance_reverts_from_completed() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        rebalancer.recordBridging(operationId, keccak256("guid"));
        rebalancer.confirmRebalance(operationId);

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.confirmRebalance(operationId);
    }

    function test_executeDock_reverts_from_failed() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.failRebalance(operationId, "failed");

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.executeDock(operationId, strategyHash);
    }

    function test_recordBridging_reverts_from_failed() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.failRebalance(operationId, "failed");

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.recordBridging(operationId, keccak256("guid"));
    }

    function test_confirmRebalance_reverts_from_failed() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.failRebalance(operationId, "failed");

        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.confirmRebalance(operationId);
    }

    // ============================================
    // SETTERS AND QUERIES
    // ============================================

    function test_setRebalancer_reverts_zero_address() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        rebalancer.setRebalancer(address(0));
    }

    function test_setRebalancer_updates_address() public {
        rebalancer.setRebalancer(other);
        assertEq(rebalancer.rebalancer(), other);
    }

    function test_operationExists_false_for_nonexistent() public view {
        assertFalse(rebalancer.operationExists(bytes32(uint256(999))));
    }

    function test_operationExists_true_for_existing() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        assertTrue(rebalancer.operationExists(operationId));
    }

    // ============================================
    // EVENT EMISSION
    // ============================================

    function test_triggerRebalance_emits_event() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        assertTrue(rebalancer.operationExists(operationId));
        (
            address lpAccount,
            uint32 opSrcChainId,
            uint32 opDstChainId,
            address opToken,
            uint256 opAmount,,
            RebalanceStatus status,,
        ) = rebalancer.operations(operationId);
        assertEq(lpAccount, address(account));
        assertEq(opSrcChainId, srcChain);
        assertEq(opDstChainId, dstChain);
        assertEq(opToken, tokenAddr);
        assertEq(opAmount, amount);
        assertEq(uint256(status), uint256(RebalanceStatus.PENDING));
    }

    function test_confirmRebalance_emits_event() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        bytes32 guid = keccak256("guid");
        rebalancer.recordBridging(operationId, guid);
        vm.expectEmit(true, true, false, false);
        emit Events.RebalanceCompleted(operationId, guid);
        rebalancer.confirmRebalance(operationId);
    }

    function test_failRebalance_emits_event() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        vm.expectEmit(true, false, false, true);
        emit Events.RebalanceFailed(operationId, "reason");
        rebalancer.failRebalance(operationId, "reason");
    }

    // ============================================
    // EXECUTE BRIDGE STARGATE TESTS
    // ============================================

    function test_executeBridgeStargate_reverts_not_docked() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        // Status is PENDING, not DOCKED
        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.executeBridgeStargate(
            operationId, 30320, address(0xCAFE), "", tokenAddr, amount, amount * 95 / 100, 128_000, 200_000
        );
    }

    function test_executeBridgeStargate_reverts_not_rebalancer() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        vm.prank(other);
        vm.expectRevert(Errors.NotRebalancer.selector);
        rebalancer.executeBridgeStargate(
            operationId, 30320, address(0xCAFE), "", tokenAddr, amount, amount * 95 / 100, 128_000, 200_000
        );
    }

    function test_executeBridgeStargate_reverts_unknown_operation() public {
        vm.expectRevert(Errors.RebalanceOperationNotFound.selector);
        rebalancer.executeBridgeStargate(
            bytes32(uint256(999)), 30320, address(0xCAFE), "", tokenAddr, amount, amount * 95 / 100, 128_000, 200_000
        );
    }

    // ============================================
    // EXECUTE BRIDGE CCTP TESTS
    // ============================================

    function test_executeBridgeCCTP_reverts_not_docked() public {
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        vm.expectRevert(Errors.InvalidInput.selector);
        rebalancer.executeBridgeCCTP(operationId, 10, address(0xCAFE), "", tokenAddr, amount, 0, 1000);
    }

    function test_executeBridgeCCTP_reverts_not_rebalancer() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        rebalancer.executeDock(operationId, strategyHash);
        vm.prank(other);
        vm.expectRevert(Errors.NotRebalancer.selector);
        rebalancer.executeBridgeCCTP(operationId, 10, address(0xCAFE), "", tokenAddr, amount, 0, 1000);
    }

    function test_executeBridgeCCTP_reverts_unknown_operation() public {
        vm.expectRevert(Errors.RebalanceOperationNotFound.selector);
        rebalancer.executeBridgeCCTP(bytes32(uint256(999)), 10, address(0xCAFE), "", tokenAddr, amount, 0, 1000);
    }

    // ============================================
    // ADDITIONAL TESTS
    // ============================================

    function testFuzz_triggerRebalance_amount(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint128).max);
        account.authorizeRebalancer(address(rebalancer));
        bytes32 operationId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, _amount);
        assertTrue(rebalancer.operationExists(operationId));
        (,,,, uint256 opAmount,,,,) = rebalancer.operations(operationId);
        assertEq(opAmount, _amount);
    }

    function test_multiple_operations_same_account() public {
        account.authorizeRebalancer(address(rebalancer));
        account.ship(strategyBytes, tokens, amounts);

        bytes32 op1 = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        vm.warp(block.timestamp + 1);
        bytes32 op2 = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        assertTrue(op1 != op2);

        rebalancer.executeDock(op1, strategyHash);
        rebalancer.recordBridging(op1, keccak256("guid-1"));
        rebalancer.confirmRebalance(op1);

        rebalancer.failRebalance(op2, "cancelled");

        (,,,,,, RebalanceStatus s1,,) = rebalancer.operations(op1);
        (,,,,,, RebalanceStatus s2,,) = rebalancer.operations(op2);
        assertEq(uint256(s1), uint256(RebalanceStatus.COMPLETED));
        assertEq(uint256(s2), uint256(RebalanceStatus.FAILED));
    }

    function test_reauthorize_after_revoke() public {
        account.authorizeRebalancer(address(rebalancer));
        assertTrue(account.rebalancerAuthorized());

        account.revokeRebalancer();
        assertFalse(account.rebalancerAuthorized());

        account.authorizeRebalancer(address(rebalancer));
        assertTrue(account.rebalancerAuthorized());
        assertEq(account.rebalancer(), address(rebalancer));

        bytes32 opId = rebalancer.triggerRebalance(address(account), srcChain, dstChain, tokenAddr, amount);
        assertTrue(rebalancer.operationExists(opId));
    }
}
