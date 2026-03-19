// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";

contract BridgeRegistryTest is Test {
    BridgeRegistry public registry;

    address public owner = address(this);
    address public other = address(0xBEEF);

    bytes32 public constant STARGATE_KEY = keccak256("STARGATE");
    bytes32 public constant CCTP_KEY = keccak256("CCTP");

    address public stargateAdapter = address(0x1111);
    address public cctpAdapter = address(0x2222);
    address public composer1 = address(0x3333);
    address public composer2 = address(0x4444);

    function setUp() public {
        registry = new BridgeRegistry(owner);
    }

    // ============================================
    // ADAPTER TESTS
    // ============================================

    function test_setAdapter_stores_address() public {
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
        assertEq(registry.getAdapter(STARGATE_KEY), stargateAdapter);
    }

    function test_setAdapter_overwrites_existing() public {
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
        address newAdapter = address(0x9999);
        registry.setAdapter(STARGATE_KEY, newAdapter);
        assertEq(registry.getAdapter(STARGATE_KEY), newAdapter);
    }

    function test_setAdapter_reverts_zero_address() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.setAdapter(STARGATE_KEY, address(0));
    }

    function test_setAdapter_reverts_not_owner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
    }

    function test_setAdapter_emits_event() public {
        vm.expectEmit(true, true, false, false);
        emit Events.AdapterSet(STARGATE_KEY, stargateAdapter);
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
    }

    function test_removeAdapter_clears_address() public {
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
        registry.removeAdapter(STARGATE_KEY);
        assertEq(registry.getAdapter(STARGATE_KEY), address(0));
    }

    function test_removeAdapter_reverts_not_registered() public {
        vm.expectRevert(Errors.AdapterNotRegistered.selector);
        registry.removeAdapter(STARGATE_KEY);
    }

    function test_removeAdapter_reverts_not_owner() public {
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        registry.removeAdapter(STARGATE_KEY);
    }

    function test_removeAdapter_emits_event() public {
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
        vm.expectEmit(true, true, false, false);
        emit Events.AdapterRemoved(STARGATE_KEY, stargateAdapter);
        registry.removeAdapter(STARGATE_KEY);
    }

    function test_getAdapter_returns_zero_for_unset() public view {
        assertEq(registry.getAdapter(STARGATE_KEY), address(0));
    }

    function test_multiple_adapters() public {
        registry.setAdapter(STARGATE_KEY, stargateAdapter);
        registry.setAdapter(CCTP_KEY, cctpAdapter);

        assertEq(registry.getAdapter(STARGATE_KEY), stargateAdapter);
        assertEq(registry.getAdapter(CCTP_KEY), cctpAdapter);
    }

    // ============================================
    // COMPOSER TESTS
    // ============================================

    function test_addComposer_sets_trusted() public {
        registry.addComposer(composer1);
        assertTrue(registry.isTrustedComposer(composer1));
    }

    function test_addComposer_reverts_zero_address() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.addComposer(address(0));
    }

    function test_addComposer_reverts_already_trusted() public {
        registry.addComposer(composer1);
        vm.expectRevert(Errors.ComposerAlreadyTrusted.selector);
        registry.addComposer(composer1);
    }

    function test_addComposer_reverts_not_owner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        registry.addComposer(composer1);
    }

    function test_addComposer_emits_event() public {
        vm.expectEmit(true, false, false, false);
        emit Events.ComposerAdded(composer1);
        registry.addComposer(composer1);
    }

    function test_removeComposer_clears_trusted() public {
        registry.addComposer(composer1);
        registry.removeComposer(composer1);
        assertFalse(registry.isTrustedComposer(composer1));
    }

    function test_removeComposer_reverts_not_trusted() public {
        vm.expectRevert(Errors.ComposerNotTrusted.selector);
        registry.removeComposer(composer1);
    }

    function test_removeComposer_reverts_not_owner() public {
        registry.addComposer(composer1);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        registry.removeComposer(composer1);
    }

    function test_removeComposer_emits_event() public {
        registry.addComposer(composer1);
        vm.expectEmit(true, false, false, false);
        emit Events.ComposerRemoved(composer1);
        registry.removeComposer(composer1);
    }

    function test_isTrustedComposer_false_by_default() public view {
        assertFalse(registry.isTrustedComposer(composer1));
    }

    function test_multiple_composers() public {
        registry.addComposer(composer1);
        registry.addComposer(composer2);

        assertTrue(registry.isTrustedComposer(composer1));
        assertTrue(registry.isTrustedComposer(composer2));

        registry.removeComposer(composer1);
        assertFalse(registry.isTrustedComposer(composer1));
        assertTrue(registry.isTrustedComposer(composer2));
    }
}
