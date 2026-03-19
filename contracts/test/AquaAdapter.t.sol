// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { AquaAdapter } from "../src/aqua/AquaAdapter.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { Errors } from "../src/lib/Errors.sol";

/// @title MockAqua
/// @notice Mock implementation of IAqua for testing
/// @dev In real Aqua: maker = msg.sender, app = first param to ship()
contract MockAqua is IAqua {
    // _balances[maker][app][strategyHash][token]
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

/// @title AquaAdapterTest
/// @notice Test suite for AquaAdapter
contract AquaAdapterTest is Test {
    AquaAdapter public adapter;
    MockAqua public mockAqua;

    address public appAddr = address(0x1234);
    address public tokenAddr = address(0x5678);
    bytes public strategyBytes = "test strategy bytes";
    bytes32 public strategyHash;
    uint256 public amount = 1000e6;

    address[] public tokens;
    uint256[] public amounts;

    function setUp() public {
        mockAqua = new MockAqua();
        adapter = new AquaAdapter(address(mockAqua));
        strategyHash = keccak256(strategyBytes);

        tokens = new address[](1);
        tokens[0] = tokenAddr;
        amounts = new uint256[](1);
        amounts[0] = amount;
    }

    function test_Ship() public {
        adapter.ship(appAddr, strategyBytes, tokens, amounts);

        // Adapter is the maker (msg.sender in Aqua), appAddr is the app
        (uint248 balance,) = mockAqua.rawBalances(address(adapter), appAddr, strategyHash, tokenAddr);
        assertEq(balance, amount);
        // Query via adapter helper
        (uint248 adapterBalance,) = adapter.getRawBalance(address(adapter), appAddr, strategyHash, tokenAddr);
        assertEq(adapterBalance, amount);
    }

    function test_Ship_RevertZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        adapter.ship(address(0), strategyBytes, tokens, amounts);
    }

    function test_Ship_RevertInvalidStrategyBytes() public {
        vm.expectRevert(Errors.InvalidStrategyBytes.selector);
        adapter.ship(appAddr, "", tokens, amounts);
    }

    function test_Ship_RevertInvalidInput_EmptyTokens() public {
        address[] memory emptyTokens = new address[](0);
        uint256[] memory emptyAmounts = new uint256[](0);
        vm.expectRevert(Errors.InvalidInput.selector);
        adapter.ship(appAddr, strategyBytes, emptyTokens, emptyAmounts);
    }

    function test_Ship_RevertInvalidInput_MismatchedArrays() public {
        uint256[] memory wrongAmounts = new uint256[](2);
        wrongAmounts[0] = amount;
        wrongAmounts[1] = amount;
        vm.expectRevert(Errors.InvalidInput.selector);
        adapter.ship(appAddr, strategyBytes, tokens, wrongAmounts);
    }

    function test_Dock() public {
        // First ship
        adapter.ship(appAddr, strategyBytes, tokens, amounts);
        (uint248 balance,) = adapter.getRawBalance(address(adapter), appAddr, strategyHash, tokenAddr);
        assertEq(balance, amount);

        // Then dock
        adapter.dock(appAddr, strategyHash, tokens);
        (uint248 afterBalance,) = adapter.getRawBalance(address(adapter), appAddr, strategyHash, tokenAddr);
        assertEq(afterBalance, 0);
    }

    function test_Dock_RevertZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        adapter.dock(address(0), strategyHash, tokens);
    }

    function test_Dock_RevertInvalidStrategy() public {
        vm.expectRevert(Errors.InvalidStrategy.selector);
        adapter.dock(appAddr, bytes32(0), tokens);
    }

    function test_GetRawBalance() public {
        adapter.ship(appAddr, strategyBytes, tokens, amounts);
        (uint248 balance, uint8 tokensCount) = adapter.getRawBalance(address(adapter), appAddr, strategyHash, tokenAddr);
        assertEq(balance, amount);
        assertEq(tokensCount, 1);
    }

    function test_AquaAddress() public view {
        assertEq(adapter.aqua(), address(mockAqua));
    }

    function testFuzz_Ship(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint128).max);
        amounts[0] = _amount;
        adapter.ship(appAddr, strategyBytes, tokens, amounts);
        (uint248 balance,) = adapter.getRawBalance(address(adapter), appAddr, strategyHash, tokenAddr);
        assertEq(balance, _amount);
    }

    function test_constructor_reverts_zero_aqua() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new AquaAdapter(address(0));
    }
}
