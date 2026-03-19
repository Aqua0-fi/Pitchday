// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { Errors } from "../src/lib/Errors.sol";
import { AccountTestHelper } from "./utils/AccountTestHelper.sol";

contract MockAquaForAccount is IAqua {
    bytes public lastStrategyBytes;
    address[] public lastTokens;
    uint256[] public lastAmounts;

    function ship(
        address,
        /* app */
        bytes memory strategy,
        address[] memory tokens,
        uint256[] memory amounts
    )
        external
        override
        returns (bytes32)
    {
        lastStrategyBytes = strategy;
        lastTokens = tokens;
        lastAmounts = amounts;
        return keccak256(strategy);
    }

    function dock(address, bytes32, address[] memory) external pure override { }

    function rawBalances(address, address, bytes32, address) external pure override returns (uint248, uint8) {
        return (0, 0);
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

contract AccountCrosschainTest is Test {
    MockAquaForAccount public aqua;
    LPAccount public accountImpl;
    UpgradeableBeacon public beacon;
    LPAccount public account;
    BridgeRegistry public bridgeRegistry;

    address public owner = address(this);
    address public factory = address(0xFACA);
    address public composer = address(0xCAFE);
    address public swapVMRouter = address(0x5555);

    function setUp() public {
        aqua = new MockAquaForAccount();
        bridgeRegistry = new BridgeRegistry(address(this));
        accountImpl = new LPAccount(address(bridgeRegistry));
        beacon = new UpgradeableBeacon(address(accountImpl), address(this));
        account = AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);
    }

    function test_onCrosschainDeposit_reverts_untrusted_composer() public {
        bytes memory strategyBytes = bytes("strategy");
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1 ether;

        // Not registered as trusted, should revert via NotAuthorized
        vm.prank(composer);
        vm.expectRevert(Errors.NotAuthorized.selector);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);
    }

    function test_onCrosschainDeposit_only_trusted_composer() public {
        bytes memory strategyBytes = bytes("strategy");
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1 ether;

        // Register composer as trusted
        bridgeRegistry.addComposer(composer);

        // Random address still can't call
        vm.prank(address(0xDEAD));
        vm.expectRevert(Errors.NotAuthorized.selector);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);

        // Trusted composer can call
        vm.prank(composer);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);
    }

    function test_onCrosschainDeposit_calls_aqua_ship() public {
        bridgeRegistry.addComposer(composer);

        bytes memory strategyBytes = bytes("strategy");
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1 ether;

        vm.prank(composer);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);

        assertEq(keccak256(aqua.lastStrategyBytes()), keccak256(strategyBytes));
        assertEq(aqua.lastTokens(0), tokens[0]);
        assertEq(aqua.lastAmounts(0), amounts[0]);
    }

    function test_onCrosschainDeposit_stores_strategy_tokens() public {
        bridgeRegistry.addComposer(composer);

        bytes memory strategyBytes = bytes("strategy");
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1 ether;

        vm.prank(composer);
        bytes32 strategyHash = account.onCrosschainDeposit(strategyBytes, tokens, amounts);

        address[] memory storedTokens = account.getStrategyTokens(strategyHash);
        assertEq(storedTokens.length, 1);
        assertEq(storedTokens[0], address(0xBEEF));
    }

    // ============================================
    // onCrosschainDeposit VALIDATION TESTS
    // ============================================

    function test_onCrosschainDeposit_reverts_empty_strategy() public {
        bridgeRegistry.addComposer(composer);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1 ether;

        vm.prank(address(composer));
        vm.expectRevert(Errors.InvalidStrategyBytes.selector);
        account.onCrosschainDeposit("", tokens, amounts);
    }

    function test_onCrosschainDeposit_reverts_empty_tokens() public {
        bridgeRegistry.addComposer(composer);

        bytes memory strategyBytes = bytes("strategy");
        address[] memory emptyTokens = new address[](0);
        uint256[] memory emptyAmounts = new uint256[](0);

        vm.prank(address(composer));
        vm.expectRevert(Errors.InvalidInput.selector);
        account.onCrosschainDeposit(strategyBytes, emptyTokens, emptyAmounts);
    }

    function test_onCrosschainDeposit_reverts_mismatched_arrays() public {
        bridgeRegistry.addComposer(composer);

        bytes memory strategyBytes = bytes("strategy");
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        uint256[] memory wrongAmounts = new uint256[](2);
        wrongAmounts[0] = 1 ether;
        wrongAmounts[1] = 1 ether;

        vm.prank(address(composer));
        vm.expectRevert(Errors.InvalidInput.selector);
        account.onCrosschainDeposit(strategyBytes, tokens, wrongAmounts);
    }

    // ============================================
    // BRIDGE REGISTRY COMPOSER MANAGEMENT
    // ============================================

    function test_removing_composer_revokes_access() public {
        bridgeRegistry.addComposer(composer);

        bytes memory strategyBytes = bytes("strategy");
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1 ether;

        // Should work while trusted
        vm.prank(composer);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);

        // Remove composer
        bridgeRegistry.removeComposer(composer);

        // Should fail after removal
        vm.prank(composer);
        vm.expectRevert(Errors.NotAuthorized.selector);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);
    }

    function test_multiple_trusted_composers() public {
        address composer2 = address(0xC002);
        bridgeRegistry.addComposer(composer);
        bridgeRegistry.addComposer(composer2);

        bytes memory strategyBytes = bytes("strategy");
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1 ether;

        // Both should work
        vm.prank(composer);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);

        vm.prank(composer2);
        account.onCrosschainDeposit(strategyBytes, tokens, amounts);
    }
}
