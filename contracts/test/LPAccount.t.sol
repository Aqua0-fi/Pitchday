// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { IERC20 } from "../src/interface/IERC20.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";
import { AccountTestHelper } from "./utils/AccountTestHelper.sol";
import {
    IStargate,
    SendParam,
    MessagingFee as SgMessagingFee,
    MessagingReceipt as SgMessagingReceipt
} from "../src/interface/IStargate.sol";

/// @title MockAqua
/// @notice Mock implementation of IAqua for testing
/// @dev Simplified 4D mapping: _balances[maker][app][strategyHash][token]
///      In real Aqua: maker = msg.sender, app = first param to ship()
contract MockAqua is IAqua {
    // _balances[maker][app][strategyHash][token]
    mapping(address => mapping(address => mapping(bytes32 => mapping(address => uint256)))) public virtualBalances;
    // Track tokens count per strategy
    mapping(address => mapping(address => mapping(bytes32 => uint8))) public tokensCounts;

    address public lastMaker;
    address public lastApp;
    bytes public lastStrategyBytes;
    bytes32 public lastStrategyHash;

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

        lastMaker = maker;
        lastApp = app;
        lastStrategyBytes = strategy;
        lastStrategyHash = strategyHash;
    }

    function dock(address app, bytes32 strategyHash, address[] memory tokens) external override {
        address maker = msg.sender;
        for (uint256 i = 0; i < tokens.length; i++) {
            virtualBalances[maker][app][strategyHash][tokens[i]] = 0;
            tokensCounts[maker][app][strategyHash] = 0xff; // docked
        }
        lastMaker = maker;
        lastApp = app;
        lastStrategyHash = strategyHash;
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

contract MockERC20 is IERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

    /// @notice MockStargateAdapter for testing bridgeStargate
    contract MockStargateAdapter {
        address public immutable tokenAddress;
        bytes32 public lastGuid;
        uint256 public lastAmount;
        bytes public lastComposeMsg;

        constructor(address _token) {
            tokenAddress = _token;
        }

        function bridgeWithCompose(
            address _token,
            uint32,
            address,
            bytes calldata _composeMsg,
            uint256 _amount,
            uint256,
            uint128,
            uint128
        ) external payable returns (bytes32 guid) {
            // Pull tokens from caller (Account)
            MockERC20(_token).transferFrom(msg.sender, address(this), _amount);
            lastAmount = _amount;
            lastComposeMsg = _composeMsg;
            guid = keccak256(abi.encode(msg.sender, _amount, block.timestamp));
            lastGuid = guid;
        }
    }

    /// @notice MockCCTPAdapter for testing bridgeCCTP
    contract MockCCTPAdapter {
        uint64 public nonceCounter;
        uint256 public lastAmount;
        bytes public lastHookData;

        function bridgeWithHook(address, uint256 _amount, uint32, address, bytes calldata _hookData, uint256, uint32)
            external
            payable
            returns (uint64 nonce)
        {
            nonceCounter++;
            lastAmount = _amount;
            lastHookData = _hookData;
            return nonceCounter;
        }
    }

    contract LPAccountTest is Test {
        MockAqua public aqua;
        MockERC20 public token;
        LPAccount public account;
        LPAccount public accountImpl;
        UpgradeableBeacon public beacon;
        BridgeRegistry public bridgeRegistry;

        address public owner = address(this);
        address public factory = address(0xFACA);
        address public rebalancerAddr = address(0xBEEF);
        address public swapVMRouter = address(0x5555);

        bytes public strategyBytes = "strategy";
        bytes32 public strategyHash;
        uint256 public amount = 1_000 ether;

        address[] public tokens;
        uint256[] public amounts;

        receive() external payable { }

        function setUp() public {
            aqua = new MockAqua();
            token = new MockERC20();

            // Deploy BridgeRegistry
            bridgeRegistry = new BridgeRegistry(address(this));

            // Deploy Account via BeaconProxy (with BridgeRegistry immutable)
            accountImpl = new LPAccount(address(bridgeRegistry));
            beacon = new UpgradeableBeacon(address(accountImpl), address(this));
            account = AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);

            strategyHash = keccak256(strategyBytes);

            // Set up arrays for ship()
            tokens = new address[](1);
            tokens[0] = address(token);
            amounts = new uint256[](1);
            amounts[0] = amount;
        }

        // ============================================
        // INITIALIZATION TESTS
        // ============================================

        function test_initialize_sets_state_correctly() public view {
            assertEq(account.owner(), owner);
            assertEq(account.FACTORY(), factory);
            assertEq(address(account.AQUA()), address(aqua));
            assertEq(account.swapVMRouter(), swapVMRouter);
            assertEq(account.BRIDGE_REGISTRY(), address(bridgeRegistry));
        }

        function test_initialize_reverts_when_called_twice() public {
            vm.expectRevert();
            account.initialize(owner, factory, address(aqua), swapVMRouter);
        }

        function test_initialize_reverts_zero_owner() public {
            bytes memory initData =
                abi.encodeCall(LPAccount.initialize, (address(0), factory, address(aqua), swapVMRouter));
            vm.expectRevert();
            new BeaconProxy(address(beacon), initData);
        }

        function test_initialize_reverts_zero_factory() public {
            bytes memory initData =
                abi.encodeCall(LPAccount.initialize, (owner, address(0), address(aqua), swapVMRouter));
            vm.expectRevert();
            new BeaconProxy(address(beacon), initData);
        }

        function test_initialize_reverts_zero_aqua() public {
            bytes memory initData = abi.encodeCall(LPAccount.initialize, (owner, factory, address(0), swapVMRouter));
            vm.expectRevert();
            new BeaconProxy(address(beacon), initData);
        }

        function test_initialize_reverts_zero_swapVMRouter() public {
            bytes memory initData = abi.encodeCall(LPAccount.initialize, (owner, factory, address(aqua), address(0)));
            vm.expectRevert();
            new BeaconProxy(address(beacon), initData);
        }

        function test_approveAqua_sets_allowance() public {
            account.approveAqua(address(token), amount);
            assertEq(token.allowance(address(account), address(aqua)), amount);
        }

        function test_ship_calls_aqua() public {
            account.ship(strategyBytes, tokens, amounts);

            (uint248 balance,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(token));
            assertEq(balance, amount);
        }

        function test_ship_stores_strategy_tokens() public {
            account.ship(strategyBytes, tokens, amounts);

            address[] memory storedTokens = account.getStrategyTokens(strategyHash);
            assertEq(storedTokens.length, 1);
            assertEq(storedTokens[0], address(token));
        }

        function test_ship_reverts_empty_bytes() public {
            vm.expectRevert(Errors.InvalidStrategyBytes.selector);
            account.ship("", tokens, amounts);
        }

        function test_ship_reverts_empty_tokens() public {
            address[] memory emptyTokens = new address[](0);
            uint256[] memory emptyAmounts = new uint256[](0);
            vm.expectRevert(Errors.InvalidInput.selector);
            account.ship(strategyBytes, emptyTokens, emptyAmounts);
        }

        function test_ship_reverts_mismatched_arrays() public {
            uint256[] memory wrongAmounts = new uint256[](2);
            wrongAmounts[0] = amount;
            wrongAmounts[1] = amount;
            vm.expectRevert(Errors.InvalidInput.selector);
            account.ship(strategyBytes, tokens, wrongAmounts);
        }

        function test_dock_by_owner() public {
            account.ship(strategyBytes, tokens, amounts);
            account.dock(strategyHash);
            (uint248 balance,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(token));
            assertEq(balance, 0);
        }

        function test_dock_by_authorized_rebalancer() public {
            account.ship(strategyBytes, tokens, amounts);
            account.authorizeRebalancer(rebalancerAddr);
            vm.prank(rebalancerAddr);
            account.dock(strategyHash);
            (uint248 balance,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(token));
            assertEq(balance, 0);
        }

        function test_dock_reverts_unauthorized() public {
            account.ship(strategyBytes, tokens, amounts);
            vm.prank(address(0xCAFE));
            vm.expectRevert(Errors.NotAuthorized.selector);
            account.dock(strategyHash);
        }

        function test_dock_reverts_no_stored_tokens() public {
            vm.expectRevert(Errors.StrategyTokensNotFound.selector);
            account.dock(keccak256("nonexistent"));
        }

        function test_withdraw_transfers_to_owner() public {
            token.mint(address(account), amount);
            uint256 beforeOwner = token.balanceOf(owner);
            account.withdraw(address(token), amount);
            assertEq(token.balanceOf(owner), beforeOwner + amount);
            assertEq(token.balanceOf(address(account)), 0);
        }

        function test_withdraw_eth_transfers_to_owner() public {
            (bool sent,) = payable(address(account)).call{ value: 1 ether }("");
            require(sent, "send failed");
            uint256 beforeOwner = owner.balance;
            account.withdrawETH(1 ether);
            assertEq(owner.balance, beforeOwner + 1 ether);
        }

        function test_authorizeRebalancer() public {
            account.authorizeRebalancer(rebalancerAddr);
            assertTrue(account.rebalancerAuthorized());
            assertEq(account.rebalancer(), rebalancerAddr);
        }

        function test_revokeRebalancer() public {
            account.authorizeRebalancer(rebalancerAddr);
            account.revokeRebalancer();
            assertFalse(account.rebalancerAuthorized());
        }

        function test_getTokenBalance() public {
            token.mint(address(account), amount);
            assertEq(account.getTokenBalance(address(token)), amount);
        }

        function test_getRawBalance() public {
            account.ship(strategyBytes, tokens, amounts);
            (uint248 balance, uint8 tokensCount) = account.getRawBalance(strategyHash, address(token));
            assertEq(balance, amount);
            assertEq(tokensCount, 1);
        }

        // ============================================
        // ACCESS CONTROL (onlyOwner) TESTS
        // ============================================

        function test_approveAqua_reverts_not_owner() public {
            vm.prank(address(0xCAFE));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
            account.approveAqua(address(token), amount);
        }

        function test_approveAqua_reverts_zero_token() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            account.approveAqua(address(0), amount);
        }

        function test_ship_reverts_not_owner() public {
            vm.prank(address(0xCAFE));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
            account.ship(strategyBytes, tokens, amounts);
        }

        function test_dock_reverts_zero_strategy_hash() public {
            vm.expectRevert(Errors.InvalidStrategy.selector);
            account.dock(bytes32(0));
        }

        function test_dock_reverts_after_revoke() public {
            account.authorizeRebalancer(rebalancerAddr);
            account.ship(strategyBytes, tokens, amounts);
            account.revokeRebalancer();
            vm.prank(rebalancerAddr);
            vm.expectRevert(Errors.NotAuthorized.selector);
            account.dock(strategyHash);
        }

        function test_withdraw_reverts_not_owner() public {
            token.mint(address(account), amount);
            vm.prank(address(0xCAFE));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
            account.withdraw(address(token), amount);
        }

        function test_withdraw_reverts_zero_token() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            account.withdraw(address(0), amount);
        }

        function test_withdraw_reverts_zero_amount() public {
            vm.expectRevert(Errors.ZeroAmount.selector);
            account.withdraw(address(token), 0);
        }

        function test_withdrawETH_reverts_not_owner() public {
            vm.deal(address(account), 1 ether);
            vm.prank(address(0xCAFE));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
            account.withdrawETH(1 ether);
        }

        function test_withdrawETH_reverts_zero_amount() public {
            vm.expectRevert(Errors.ZeroAmount.selector);
            account.withdrawETH(0);
        }

        function test_withdrawETH_reverts_insufficient_balance() public {
            vm.expectRevert(Errors.InsufficientBalance.selector);
            account.withdrawETH(1 ether);
        }

        function test_authorizeRebalancer_reverts_not_owner() public {
            vm.prank(address(0xCAFE));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
            account.authorizeRebalancer(rebalancerAddr);
        }

        function test_authorizeRebalancer_reverts_zero_address() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            account.authorizeRebalancer(address(0));
        }

        function test_revokeRebalancer_reverts_not_owner() public {
            vm.prank(address(0xCAFE));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
            account.revokeRebalancer();
        }

        // ============================================
        // EVENT EMISSION TESTS
        // ============================================

        function test_withdraw_emits_Withdrawn() public {
            token.mint(address(account), amount);
            vm.expectEmit(true, true, false, true);
            emit Events.Withdrawn(address(account), address(token), amount, owner);
            account.withdraw(address(token), amount);
        }

        function test_authorizeRebalancer_emits_event() public {
            vm.expectEmit(true, true, false, false);
            emit Events.RebalancerAuthorized(address(account), rebalancerAddr);
            account.authorizeRebalancer(rebalancerAddr);
        }

        function test_revokeRebalancer_emits_event() public {
            account.authorizeRebalancer(rebalancerAddr);
            vm.expectEmit(true, false, false, false);
            emit Events.RebalancerRevoked(address(account));
            account.revokeRebalancer();
        }

        // ============================================
        // MULTI-TOKEN AND FUZZ TESTS
        // ============================================

        function test_ship_multiple_tokens() public {
            MockERC20 token2 = new MockERC20();
            address[] memory multiTokens = new address[](2);
            multiTokens[0] = address(token);
            multiTokens[1] = address(token2);
            uint256[] memory multiAmounts = new uint256[](2);
            multiAmounts[0] = 500 ether;
            multiAmounts[1] = 300 ether;

            bytes32 hash = account.ship(strategyBytes, multiTokens, multiAmounts);

            (uint248 bal0,) = account.getRawBalance(hash, address(token));
            (uint248 bal1,) = account.getRawBalance(hash, address(token2));
            assertEq(bal0, 500 ether);
            assertEq(bal1, 300 ether);

            address[] memory storedTokens = account.getStrategyTokens(hash);
            assertEq(storedTokens.length, 2);
        }

        function testFuzz_ship(uint256 _amount) public {
            _amount = bound(_amount, 1, type(uint128).max);
            amounts[0] = _amount;
            bytes32 hash = account.ship(strategyBytes, tokens, amounts);
            (uint248 balance,) = account.getRawBalance(hash, address(token));
            assertEq(balance, _amount);
        }

        function testFuzz_withdraw(uint256 _amount) public {
            _amount = bound(_amount, 1, type(uint128).max);
            token.mint(address(account), _amount);
            uint256 beforeBal = token.balanceOf(owner);
            account.withdraw(address(token), _amount);
            assertEq(token.balanceOf(owner), beforeBal + _amount);
        }

        // ============================================
        // ADDITIONAL UNIT TESTS
        // ============================================

        function test_ship_after_dock_same_strategy() public {
            account.ship(strategyBytes, tokens, amounts);
            account.dock(strategyHash);

            bytes32 hash2 = account.ship(strategyBytes, tokens, amounts);
            assertEq(hash2, strategyHash);

            (uint248 balance,) = account.getRawBalance(hash2, address(token));
            assertEq(balance, amount);
        }

        function test_ship_after_dock_different_strategy() public {
            account.ship(strategyBytes, tokens, amounts);
            account.dock(strategyHash);

            bytes memory strategyB = "strategy-B";
            bytes32 hashB = account.ship(strategyB, tokens, amounts);
            assertTrue(hashB != strategyHash, "different strategy should give different hash");

            (uint248 balance,) = account.getRawBalance(hashB, address(token));
            assertEq(balance, amount);
        }

        function test_dock_twice_second_succeeds_in_mock() public {
            account.ship(strategyBytes, tokens, amounts);
            account.dock(strategyHash);
            account.dock(strategyHash);

            (uint248 balance, uint8 tokensCount) =
                aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(token));
            assertEq(balance, 0);
            assertEq(tokensCount, 0xff);
        }

        function test_setSwapVMRouter() public {
            address newRouter = address(0x6666);
            account.setSwapVMRouter(newRouter);
            assertEq(account.swapVMRouter(), newRouter);
        }

        function test_setSwapVMRouter_reverts_not_owner() public {
            vm.prank(address(0xCAFE));
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
            account.setSwapVMRouter(address(0x6666));
        }

        function test_setSwapVMRouter_reverts_zero_address() public {
            vm.expectRevert(Errors.ZeroAddress.selector);
            account.setSwapVMRouter(address(0));
        }

        function test_setSwapVMRouter_emits_event() public {
            address newRouter = address(0x6666);
            vm.expectEmit(true, true, false, false);
            emit Events.SwapVMRouterSet(swapVMRouter, newRouter);
            account.setSwapVMRouter(newRouter);
        }

        function testFuzz_ship_multiple_tokens(uint256 a, uint256 b) public {
            a = bound(a, 1, type(uint128).max);
            b = bound(b, 1, type(uint128).max);

            MockERC20 token2 = new MockERC20();
            address[] memory multiTokens = new address[](2);
            multiTokens[0] = address(token);
            multiTokens[1] = address(token2);
            uint256[] memory multiAmounts = new uint256[](2);
            multiAmounts[0] = a;
            multiAmounts[1] = b;

            bytes32 hash = account.ship(strategyBytes, multiTokens, multiAmounts);

            (uint248 bal0,) = account.getRawBalance(hash, address(token));
            (uint248 bal1,) = account.getRawBalance(hash, address(token2));
            assertEq(bal0, a);
            assertEq(bal1, b);
        }

        // ============================================
        // STARGATE BRIDGE TESTS
        // ============================================

        function test_bridgeStargate_as_owner() public {
            MockStargateAdapter mockAdapter = new MockStargateAdapter(address(token));
            bridgeRegistry.setAdapter(account.STARGATE_KEY(), address(mockAdapter));

            // Fund account with tokens
            token.mint(address(account), amount);

            bytes memory composeMsg = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            bytes32 guid = account.bridgeStargate(
                30320, address(0xCAFE), composeMsg, address(token), amount, amount * 95 / 100, 128_000, 200_000
            );

            assertTrue(guid != bytes32(0));
            assertEq(mockAdapter.lastAmount(), amount);
        }

        function test_bridgeStargate_as_rebalancer() public {
            MockStargateAdapter mockAdapter = new MockStargateAdapter(address(token));
            bridgeRegistry.setAdapter(account.STARGATE_KEY(), address(mockAdapter));
            account.authorizeRebalancer(rebalancerAddr);

            token.mint(address(account), amount);

            bytes memory composeMsg = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            vm.prank(rebalancerAddr);
            bytes32 guid = account.bridgeStargate(
                30320, address(0xCAFE), composeMsg, address(token), amount, amount * 95 / 100, 128_000, 200_000
            );

            assertTrue(guid != bytes32(0));
        }

        function test_bridgeStargate_reverts_unauthorized() public {
            MockStargateAdapter mockAdapter = new MockStargateAdapter(address(token));
            bridgeRegistry.setAdapter(account.STARGATE_KEY(), address(mockAdapter));

            bytes memory composeMsg = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            vm.prank(address(0xCAFE));
            vm.expectRevert(Errors.NotAuthorized.selector);
            account.bridgeStargate(
                30320, address(0xCAFE), composeMsg, address(token), amount, amount * 95 / 100, 128_000, 200_000
            );
        }

        function test_bridgeStargate_reverts_no_adapter() public {
            bytes memory composeMsg = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            vm.expectRevert(Errors.ZeroAddress.selector);
            account.bridgeStargate(
                30320, address(0xCAFE), composeMsg, address(token), amount, amount * 95 / 100, 128_000, 200_000
            );
        }

        function test_bridgeStargate_reverts_zero_token() public {
            bridgeRegistry.setAdapter(account.STARGATE_KEY(), address(0x7777));
            bytes memory composeMsg = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            vm.expectRevert(Errors.ZeroAddress.selector);
            account.bridgeStargate(
                30320, address(0xCAFE), composeMsg, address(0), amount, amount * 95 / 100, 128_000, 200_000
            );
        }

        function test_bridgeStargate_reverts_zero_amount() public {
            bridgeRegistry.setAdapter(account.STARGATE_KEY(), address(0x7777));
            bytes memory composeMsg = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            vm.expectRevert(Errors.ZeroAmount.selector);
            account.bridgeStargate(30320, address(0xCAFE), composeMsg, address(token), 0, 0, 128_000, 200_000);
        }

        // ============================================
        // CCTP BRIDGE TESTS
        // ============================================

        function test_bridgeCCTP_as_owner() public {
            MockCCTPAdapter mockAdapter = new MockCCTPAdapter();
            bridgeRegistry.setAdapter(account.CCTP_KEY(), address(mockAdapter));

            token.mint(address(account), amount);
            account.approveAqua(address(token), 0); // reset

            bytes memory hookData = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            uint64 nonce = account.bridgeCCTP(10, address(0xCAFE), hookData, address(token), amount, 0, 1000);

            assertEq(nonce, 1);
            assertEq(mockAdapter.lastAmount(), amount);
        }

        function test_bridgeCCTP_reverts_no_adapter() public {
            bytes memory hookData = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            vm.expectRevert(Errors.ZeroAddress.selector);
            account.bridgeCCTP(10, address(0xCAFE), hookData, address(token), amount, 0, 1000);
        }

        function test_bridgeCCTP_reverts_unauthorized() public {
            MockCCTPAdapter mockAdapter = new MockCCTPAdapter();
            bridgeRegistry.setAdapter(account.CCTP_KEY(), address(mockAdapter));

            bytes memory hookData = abi.encode(address(0xDEAD), "strategy", new address[](0), new uint256[](0));
            vm.prank(address(0xCAFE));
            vm.expectRevert(Errors.NotAuthorized.selector);
            account.bridgeCCTP(10, address(0xCAFE), hookData, address(token), amount, 0, 1000);
        }

        // ============================================
        // ONLY COMPOSER (BRIDGE REGISTRY) TESTS
        // ============================================

        function test_onCrosschainDeposit_reverts_untrusted_composer() public {
            vm.prank(address(0xDEAD));
            vm.expectRevert(Errors.NotAuthorized.selector);
            account.onCrosschainDeposit(strategyBytes, tokens, amounts);
        }

        function test_onCrosschainDeposit_from_trusted_composer() public {
            address composerAddr = address(0xC001);
            bridgeRegistry.addComposer(composerAddr);

            vm.prank(composerAddr);
            bytes32 hash = account.onCrosschainDeposit(strategyBytes, tokens, amounts);

            assertEq(hash, strategyHash);
            (uint248 balance,) = aqua.rawBalances(address(account), swapVMRouter, strategyHash, address(token));
            assertEq(balance, amount);
        }
    }
