// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { IAqua } from "../src/interface/IAqua.sol";
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

    function safeBalances(address, address, bytes32, address, address)
        external
        pure
        override
        returns (uint256, uint256)
    {
        return (0, 0);
    }
}

contract AccountUpgradeTest is Test {
    MockAqua public aqua;
    BridgeRegistry public bridgeRegistry;
    LPAccount public accountImpl;
    UpgradeableBeacon public beacon;
    LPAccount public account;

    address public owner = address(this);
    address public factory = address(0xFACA);
    address public swapVMRouter = address(0x5555);
    address public rebalancerAddr = address(0xBEEF);

    bytes public strategyBytes = "upgrade-test-strategy";
    bytes32 public strategyHash;

    function setUp() public {
        aqua = new MockAqua();
        bridgeRegistry = new BridgeRegistry(owner);

        // Deploy v1 implementation and beacon
        accountImpl = new LPAccount(address(bridgeRegistry));
        beacon = new UpgradeableBeacon(address(accountImpl), address(this));

        // Deploy account proxy
        account = AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);
        strategyHash = keccak256(strategyBytes);
    }

    function test_upgrade_preserves_owner() public {
        // Set state
        account.authorizeRebalancer(rebalancerAddr);

        // Upgrade to v2
        LPAccount newImpl = new LPAccount(address(bridgeRegistry));
        beacon.upgradeTo(address(newImpl));

        // Verify state preserved
        assertEq(account.owner(), owner);
        assertEq(account.rebalancer(), rebalancerAddr);
        assertTrue(account.rebalancerAuthorized());
    }

    function test_upgrade_preserves_strategy_tokens() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x70CE4);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 ether;

        // Ship a strategy
        account.ship(strategyBytes, tokens, amounts);

        // Verify stored
        address[] memory storedBefore = account.getStrategyTokens(strategyHash);
        assertEq(storedBefore.length, 1);

        // Upgrade
        LPAccount newImpl = new LPAccount(address(bridgeRegistry));
        beacon.upgradeTo(address(newImpl));

        // Verify preserved
        address[] memory storedAfter = account.getStrategyTokens(strategyHash);
        assertEq(storedAfter.length, 1);
        assertEq(storedAfter[0], tokens[0]);
    }

    function test_upgrade_preserves_aqua_and_factory() public {
        // Upgrade
        LPAccount newImpl = new LPAccount(address(bridgeRegistry));
        beacon.upgradeTo(address(newImpl));

        // Verify immutable/storage preserved
        assertEq(account.FACTORY(), factory);
        assertEq(address(account.AQUA()), address(aqua));
        assertEq(account.swapVMRouter(), swapVMRouter);
        assertEq(account.BRIDGE_REGISTRY(), address(bridgeRegistry));
    }

    function test_upgrade_ship_and_dock_still_work() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x70CE4);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 500 ether;

        // Ship before upgrade
        account.ship(strategyBytes, tokens, amounts);

        // Upgrade
        LPAccount newImpl = new LPAccount(address(bridgeRegistry));
        beacon.upgradeTo(address(newImpl));

        // Dock after upgrade
        account.dock(strategyHash);

        (uint248 balance, uint8 tokensCount) =
            aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(0x70CE4));
        assertEq(balance, 0);
        assertEq(tokensCount, 0xff);

        // Ship again after upgrade
        bytes32 hash2 = account.ship(strategyBytes, tokens, amounts);
        assertEq(hash2, strategyHash);

        (uint248 bal2,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(0x70CE4));
        assertEq(bal2, 500 ether);
    }

    function test_upgrade_multiple_accounts_share_implementation() public {
        LPAccount account2 =
            AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);

        // Ship on both before upgrade
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x70CE4);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        account.ship(strategyBytes, tokens, amounts);
        account2.ship(strategyBytes, tokens, amounts);

        // Upgrade — affects all accounts
        LPAccount newImpl = new LPAccount(address(bridgeRegistry));
        beacon.upgradeTo(address(newImpl));

        // Both still work
        (uint248 bal1,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(0x70CE4));
        (uint248 bal2,) = aqua.rawBalances(address(account2), swapVMRouter, strategyHash, address(0x70CE4));
        assertEq(bal1, 100 ether);
        assertEq(bal2, 100 ether);

        // Dock on both after upgrade
        account.dock(strategyHash);
        account2.dock(strategyHash);
    }
}
