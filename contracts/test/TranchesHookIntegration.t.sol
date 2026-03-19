// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/libraries/TransientStateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SharedLiquidityPool} from "../src/v4/SharedLiquidityPool.sol";
import {TranchesHook} from "../src/v4/tranches/TranchesHook.sol";
import {TranchesRouter} from "../src/v4/tranches/TranchesRouter.sol";

/// @dev Minimal ERC20 for fork test (deployed fresh on the fork)
contract TestToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @dev Minimal swap router — unlocks PoolManager + executes swap + settles
contract SimpleSwapRouter {
    using TransientStateLibrary for IPoolManager;

    IPoolManager public immutable pm;

    struct SwapCallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
    }

    constructor(IPoolManager _pm) { pm = _pm; }

    function swap(PoolKey memory key, SwapParams memory params) external returns (BalanceDelta delta) {
        bytes memory data = abi.encode(SwapCallbackData(msg.sender, key, params));
        delta = abi.decode(pm.unlock(data), (BalanceDelta));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(pm));
        SwapCallbackData memory data = abi.decode(rawData, (SwapCallbackData));
        BalanceDelta delta = pm.swap(data.key, data.params, "");

        // Read outstanding deltas from transient storage (includes hook-modified deltas)
        int256 delta0 = pm.currencyDelta(address(this), data.key.currency0);
        int256 delta1 = pm.currencyDelta(address(this), data.key.currency1);

        _settle(data.key.currency0, data.sender, delta0);
        _settle(data.key.currency1, data.sender, delta1);

        return abi.encode(delta);
    }

    function _settle(Currency currency, address sender, int256 amount) internal {
        if (amount < 0) {
            uint256 owed = uint256(-amount);
            pm.sync(currency);
            IERC20(Currency.unwrap(currency)).transferFrom(sender, address(pm), owed);
            pm.settle();
        } else if (amount > 0) {
            pm.take(currency, sender, uint256(amount));
        }
    }
}

/// @dev Minimal modify-liquidity router
contract SimpleLiquidityRouter {
    using TransientStateLibrary for IPoolManager;

    IPoolManager public immutable pm;

    struct LiqCallbackData {
        address sender;
        PoolKey key;
        ModifyLiquidityParams params;
        bytes hookData;
    }

    constructor(IPoolManager _pm) { pm = _pm; }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes memory hookData)
        external
        returns (BalanceDelta delta)
    {
        bytes memory data = abi.encode(LiqCallbackData(msg.sender, key, params, hookData));
        delta = abi.decode(pm.unlock(data), (BalanceDelta));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(pm));
        LiqCallbackData memory data = abi.decode(rawData, (LiqCallbackData));
        (BalanceDelta delta,) = pm.modifyLiquidity(data.key, data.params, data.hookData);

        // Read outstanding deltas from transient storage (includes hook-modified deltas)
        int256 delta0 = pm.currencyDelta(address(this), data.key.currency0);
        int256 delta1 = pm.currencyDelta(address(this), data.key.currency1);

        _settle(data.key.currency0, data.sender, delta0);
        _settle(data.key.currency1, data.sender, delta1);

        return abi.encode(delta);
    }

    function _settle(Currency currency, address sender, int256 amount) internal {
        if (amount < 0) {
            uint256 owed = uint256(-amount);
            pm.sync(currency);
            IERC20(Currency.unwrap(currency)).transferFrom(sender, address(pm), owed);
            pm.settle();
        } else if (amount > 0) {
            pm.take(currency, sender, uint256(amount));
        }
    }
}

/// @title TranchesHook Fork Integration Test
/// @notice Forks Unichain Sepolia (PoolManager at known address), deploys fresh tokens +
///         SharedLiquidityPool + TranchesHook + Router, then runs the full tranche lifecycle.
/// @dev Run with: UNICHAIN_RPC_URL=https://sepolia.unichain.org forge test --match-path test/TranchesHookIntegration.t.sol -vvv
contract TranchesHookIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // ─── Known on-chain addresses (Unichain Sepolia) ─────────────────────
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    // ─── Contracts ────────────────────────────────────────────────────────
    IPoolManager manager;
    SharedLiquidityPool sharedPool;
    TranchesHook hook;
    TranchesRouter tranchesRouter;
    SimpleSwapRouter swapRouter;
    SimpleLiquidityRouter liqRouter;

    TestToken tokenA;
    TestToken tokenB;
    Currency currency0;
    Currency currency1;

    // ─── Actors ───────────────────────────────────────────────────────────
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    // ─── Pool ─────────────────────────────────────────────────────────────
    PoolKey poolKey;
    PoolId poolId;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // Hook flags: afterInit | afterAddLiq | afterRemoveLiq | beforeSwap | afterSwap | afterSwapRetDelta | afterRemoveLiqRetDelta
    uint160 constant HOOK_FLAGS =
        uint160((1 << 12) | (1 << 10) | (1 << 8) | (1 << 7) | (1 << 6) | (1 << 2) | (1 << 0));

    function setUp() public {
        // Skip if no RPC available
        string memory rpc = vm.envOr("UNICHAIN_RPC_URL", string("https://sepolia.unichain.org"));
        vm.createSelectFork(rpc);

        manager = IPoolManager(POOL_MANAGER);

        // Deploy fresh tokens
        tokenA = new TestToken("TokenA", "TKA");
        tokenB = new TestToken("TokenB", "TKB");
        if (address(tokenA) < address(tokenB)) {
            currency0 = Currency.wrap(address(tokenA));
            currency1 = Currency.wrap(address(tokenB));
        } else {
            currency0 = Currency.wrap(address(tokenB));
            currency1 = Currency.wrap(address(tokenA));
        }

        // Deploy infrastructure
        sharedPool = new SharedLiquidityPool(address(this));
        swapRouter = new SimpleSwapRouter(manager);
        liqRouter = new SimpleLiquidityRouter(manager);

        // Deploy hook at address with correct permission bits
        address hookAddr = address(HOOK_FLAGS);
        deployCodeTo("TranchesHook.sol:TranchesHook", abi.encode(manager, sharedPool, address(this)), hookAddr);
        hook = TranchesHook(payable(hookAddr));

        // Wire up (no setHook needed — new SharedLiquidityPool uses IAqua0BaseHookMarker interface check)
        tranchesRouter = new TranchesRouter(manager, hook, sharedPool);
        hook.setTrustedRouter(address(tranchesRouter));

        // Mint tokens
        _mintTokens(address(this), 10_000e18);
        _mintTokens(alice, 1000e18);
        _mintTokens(bob, 1000e18);
        _mintTokens(charlie, 1000e18);

        // Approvals
        _approveAll(address(this));
        _approveAllAs(alice);
        _approveAllAs(bob);
        _approveAllAs(charlie);

        // SharedPool -> Hook approval (for settleSwapDelta)
        vm.startPrank(address(sharedPool));
        TestToken(Currency.unwrap(currency0)).approve(hookAddr, type(uint256).max);
        TestToken(Currency.unwrap(currency1)).approve(hookAddr, type(uint256).max);
        vm.stopPrank();

        // Initialize pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hookAddr));
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Base liquidity (no hookData => no tranche tracking)
        liqRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100e18, salt: bytes32(0)}),
            ""
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 1: Pool init + tranche deposits
    // ═══════════════════════════════════════════════════════════════════

    function test_poolInitAndTrancheDeposits() public {
        (uint256 ts, uint256 tj,,,uint256 apy,) = hook.getPoolStats(poolKey);
        assertEq(ts, 0);
        assertEq(tj, 0);
        assertEq(apy, 500);

        _depositTranches(10e18, 10e18);

        (ts, tj,,,,) = hook.getPoolStats(poolKey);
        assertEq(ts, 10e18, "Senior deposited");
        assertEq(tj, 10e18, "Junior deposited");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 2: Swaps distribute tranche fees
    // ═══════════════════════════════════════════════════════════════════

    function test_swapDistributesTrancheFees() public {
        _depositTranches(10e18, 10e18);
        vm.warp(block.timestamp + 12);

        _doSwap(true, -1e18);

        (,, uint256 sf, uint256 jf,,) = hook.getPoolStats(poolKey);
        assertGt(sf + jf, 0, "Fees distributed");
        assertGe(sf, jf, "Senior >= Junior");
        console.log("Senior:", sf, "Junior:", jf);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 3: Swaps with JIT from SharedPool
    // ═══════════════════════════════════════════════════════════════════

    function test_swapWithJIT() public {
        _depositTranches(10e18, 10e18);
        _setupJIT(charlie, 50e18, 50e18);
        vm.warp(block.timestamp + 12);

        _doSwap(true, -1e18);

        (,, uint256 sf, uint256 jf,,) = hook.getPoolStats(poolKey);
        assertGt(sf + jf, 0, "Fees with JIT");
        console.log("[JIT] Senior:", sf, "Junior:", jf);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 4: Multiple swaps accumulate
    // ═══════════════════════════════════════════════════════════════════

    function test_multiSwaps() public {
        _depositTranches(10e18, 10e18);

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 12);
            _doSwap(i % 2 == 0, -0.5e18);
        }

        (uint256 ap0, uint256 ap1) = hook.pendingFees(alice, poolKey);
        (uint256 bp0, uint256 bp1) = hook.pendingFees(bob, poolKey);
        assertGt(ap0 + ap1 + bp0 + bp1, 0, "Fees accumulated");
        console.log("Alice:", ap0, ap1);
        console.log("Bob:", bp0, bp1);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 5: RSC adjusts APY
    // ═══════════════════════════════════════════════════════════════════

    function test_rscAdjust() public {
        _depositTranches(10e18, 10e18);
        address rsc = makeAddr("rsc");
        hook.setAuthorizedRSC(rsc);

        vm.prank(rsc);
        hook.adjustRiskParameter(poolKey, 1000);

        (,,,, uint256 apy,) = hook.getPoolStats(poolKey);
        assertEq(apy, 1000);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 6: Claim + withdraw
    // ═══════════════════════════════════════════════════════════════════

    function test_claimAndWithdraw() public {
        _depositTranches(10e18, 10e18);

        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 12);
            _doSwap(i % 2 == 0, -0.5e18);
        }

        // Advance past MIN_BLOCKS_LOCK before claiming (Fix #3: claimFees now has block lock)
        vm.roll(block.number + 101);

        vm.prank(alice);
        hook.claimFees(poolKey);

        uint256 c0 = hook.claimableBalance(alice, currency0);
        uint256 c1 = hook.claimableBalance(alice, currency1);
        assertGt(c0 + c1, 0, "Alice has claimable");

        if (c0 > 0) {
            uint256 before = TestToken(Currency.unwrap(currency0)).balanceOf(alice);
            vm.prank(alice);
            hook.withdrawFees(currency0);
            assertEq(TestToken(Currency.unwrap(currency0)).balanceOf(alice) - before, c0);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 7: Full lifecycle with JIT
    // ═══════════════════════════════════════════════════════════════════

    function test_fullLifecycle() public {
        _depositTranches(10e18, 10e18);
        _setupJIT(charlie, 50e18, 50e18);

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 12);
            _doSwap(i % 2 == 0, -0.5e18);
        }

        (uint256 ts, uint256 tj, uint256 sf, uint256 jf, uint256 apy, uint256 ratio) = hook.getPoolStats(poolKey);
        console.log("=== Full Lifecycle ===");
        console.log("Senior:", ts, "Junior:", tj);
        console.log("Fees:", sf, jf);
        assertEq(ts, 10e18);
        assertEq(tj, 10e18);
        assertGt(sf + jf, 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 8: recordVirtualDeposit — direct registration via trusted router
    // ═══════════════════════════════════════════════════════════════════

    function test_recordVirtualDeposit() public {
        // Alice deposits Senior via virtual path (simulating what the new router will do)
        vm.prank(address(tranchesRouter));
        hook.recordVirtualDeposit(alice, poolKey, TranchesHook.Tranche.SENIOR, 10e18);

        // Bob deposits Junior
        vm.prank(address(tranchesRouter));
        hook.recordVirtualDeposit(bob, poolKey, TranchesHook.Tranche.JUNIOR, 10e18);

        // Verify pool stats
        (uint256 ts, uint256 tj,,,uint256 apy,) = hook.getPoolStats(poolKey);
        assertEq(ts, 10e18, "Senior deposited via virtual");
        assertEq(tj, 10e18, "Junior deposited via virtual");
        assertEq(apy, 500, "Default APY");

        // Verify position exists
        bytes32 posKey = keccak256(abi.encodePacked(alice, PoolId.unwrap(poolId)));
        (TranchesHook.Tranche tranche, uint256 amount, uint256 depositBlock,,,) = hook.positions(posKey);
        assertEq(uint8(tranche), 0, "Senior = 0");
        assertEq(amount, 10e18, "Position amount");
        assertEq(depositBlock, block.number, "Deposit block");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 9: recordVirtualDeposit — only trusted router can call
    // ═══════════════════════════════════════════════════════════════════

    function test_recordVirtualDeposit_onlyRouter() public {
        // Random address should revert
        vm.prank(alice);
        vm.expectRevert(TranchesHook.NotTrustedRouter.selector);
        hook.recordVirtualDeposit(alice, poolKey, TranchesHook.Tranche.SENIOR, 10e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 10: recordVirtualDeposit — senior ratio cap enforced
    // ═══════════════════════════════════════════════════════════════════

    function test_recordVirtualDeposit_seniorRatioCap() public {
        // First deposit Junior (small)
        vm.prank(address(tranchesRouter));
        hook.recordVirtualDeposit(bob, poolKey, TranchesHook.Tranche.JUNIOR, 1e18);

        // Try to deposit way too much Senior (would exceed 80% ratio)
        vm.prank(address(tranchesRouter));
        vm.expectRevert(); // SeniorRatioExceeded
        hook.recordVirtualDeposit(alice, poolKey, TranchesHook.Tranche.SENIOR, 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 11: recordVirtualWithdrawal — full withdrawal
    // ═══════════════════════════════════════════════════════════════════

    function test_recordVirtualWithdrawal() public {
        // Deposit via virtual path
        vm.prank(address(tranchesRouter));
        hook.recordVirtualDeposit(alice, poolKey, TranchesHook.Tranche.SENIOR, 10e18);

        // Advance blocks past MIN_BLOCKS_LOCK
        vm.roll(block.number + 101);

        // Withdraw
        vm.prank(address(tranchesRouter));
        hook.recordVirtualWithdrawal(alice, poolKey, 0); // 0 = full position

        // Verify position is gone
        (uint256 ts,,,,,) = hook.getPoolStats(poolKey);
        assertEq(ts, 0, "Senior should be 0 after withdrawal");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 12: recordVirtualWithdrawal — anti flash-loan lock
    // ═══════════════════════════════════════════════════════════════════

    function test_recordVirtualWithdrawal_lockPreventsFlashLoan() public {
        vm.prank(address(tranchesRouter));
        hook.recordVirtualDeposit(alice, poolKey, TranchesHook.Tranche.SENIOR, 10e18);

        // Try to withdraw immediately (should fail — MIN_BLOCKS_LOCK = 100)
        vm.prank(address(tranchesRouter));
        vm.expectRevert(); // MinBlockLockNotMet
        hook.recordVirtualWithdrawal(alice, poolKey, 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 13: recordVirtualDeposit + swap = fees accumulate
    // ═══════════════════════════════════════════════════════════════════

    function test_virtualDepositWithSwapFees() public {
        // Virtual deposits
        vm.prank(address(tranchesRouter));
        hook.recordVirtualDeposit(alice, poolKey, TranchesHook.Tranche.SENIOR, 10e18);
        vm.prank(address(tranchesRouter));
        hook.recordVirtualDeposit(bob, poolKey, TranchesHook.Tranche.JUNIOR, 10e18);

        vm.warp(block.timestamp + 12);

        // Swap generates fees (base liquidity from setUp handles the swap)
        _doSwap(true, -1e18);

        // Check fees distributed
        (,, uint256 sf, uint256 jf,,) = hook.getPoolStats(poolKey);
        assertGt(sf + jf, 0, "Fees should distribute to virtual tranche positions");
        assertGe(sf, jf, "Senior >= Junior (waterfall)");
        console.log("[Virtual] Senior fees:", sf, "Junior fees:", jf);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Phase 3: E2E — Virtual Tranches via SharedPool + JIT
    // ═══════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════
    //  Test 14: Full router addLiquidity (SharedPool virtual flow)
    // ═══════════════════════════════════════════════════════════════════

    function test_virtualAddLiquidity_fullRouter() public {
        address t0 = Currency.unwrap(currency0);
        address t1 = Currency.unwrap(currency1);

        uint256 aliceBal0Before = TestToken(t0).balanceOf(alice);
        uint256 aliceBal1Before = TestToken(t1).balanceOf(alice);

        // Alice deposits Senior via virtual SharedPool path
        vm.prank(alice);
        tranchesRouter.addLiquidity(
            poolKey, -120, 120, 10e18, 50e18, 50e18, TranchesHook.Tranche.SENIOR
        );

        // Tokens moved from Alice to SharedPool
        assertEq(aliceBal0Before - TestToken(t0).balanceOf(alice), 50e18, "Alice spent 50 token0");
        assertEq(aliceBal1Before - TestToken(t1).balanceOf(alice), 50e18, "Alice spent 50 token1");

        // Router's freeBalance in SharedPool
        assertEq(sharedPool.freeBalance(address(tranchesRouter), t0), 50e18, "Router free0 = 50");
        assertEq(sharedPool.freeBalance(address(tranchesRouter), t1), 50e18, "Router free1 = 50");

        // Hook tracks Alice as Senior
        (uint256 ts, uint256 tj,,,,) = hook.getPoolStats(poolKey);
        assertEq(ts, 10e18, "Senior tracked in hook");
        assertEq(tj, 0, "No junior yet");

        // Position exists in hook
        bytes32 posKey = keccak256(abi.encodePacked(alice, PoolId.unwrap(poolId)));
        (TranchesHook.Tranche tranche, uint256 amount,,,,) = hook.positions(posKey);
        assertEq(uint8(tranche), 0, "Senior = 0");
        assertEq(amount, 10e18, "10e18 liquidity");

        console.log("[Router] Alice deposited Senior via SharedPool path");
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 15: Full router removeLiquidity (SharedPool virtual flow)
    // ═══════════════════════════════════════════════════════════════════

    function test_virtualRemoveLiquidity_fullRouter() public {
        address t0 = Currency.unwrap(currency0);
        address t1 = Currency.unwrap(currency1);

        // Deposit via router
        vm.prank(alice);
        tranchesRouter.addLiquidity(
            poolKey, -120, 120, 10e18, 50e18, 50e18, TranchesHook.Tranche.SENIOR
        );

        uint256 aliceBal0Before = TestToken(t0).balanceOf(alice);
        uint256 aliceBal1Before = TestToken(t1).balanceOf(alice);

        // Advance past MIN_BLOCKS_LOCK
        vm.roll(block.number + 101);

        // Remove via router
        vm.prank(alice);
        tranchesRouter.removeLiquidity(poolKey, -120, 120, 50e18, 50e18);

        // Tokens returned to Alice
        uint256 aliceGot0 = TestToken(t0).balanceOf(alice) - aliceBal0Before;
        uint256 aliceGot1 = TestToken(t1).balanceOf(alice) - aliceBal1Before;
        assertGt(aliceGot0, 0, "Alice got token0 back");
        assertGt(aliceGot1, 0, "Alice got token1 back");

        // Position removed from hook
        (uint256 ts,,,,,) = hook.getPoolStats(poolKey);
        assertEq(ts, 0, "Senior = 0 after removal");

        // Router freeBalance cleared
        assertEq(sharedPool.freeBalance(address(tranchesRouter), t0), 0, "Router free0 = 0");
        assertEq(sharedPool.freeBalance(address(tranchesRouter), t1), 0, "Router free1 = 0");

        console.log("[Router] Alice removed:", aliceGot0, aliceGot1);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 16: JIT + Virtual Tranches full E2E
    //  Alice (Senior) + Bob (Junior) deposit via SharedPool → JIT fires
    //  on swap → PnL distributed → tranche fees accumulated
    // ═══════════════════════════════════════════════════════════════════

    function test_jitVirtualLiquidityFullFlow() public {
        address t0 = Currency.unwrap(currency0);
        address t1 = Currency.unwrap(currency1);

        // Virtual deposits: Alice Senior (-120/120), Bob Junior (-240/240)
        // Different tick ranges because SharedPool rejects duplicate positions per user (router)
        _depositVirtualTranches(10e18, 50e18, 10e18, 50e18);

        // Snapshot router freeBalance after deposits
        uint256 routerFree0Before = sharedPool.freeBalance(address(tranchesRouter), t0);
        uint256 routerFree1Before = sharedPool.freeBalance(address(tranchesRouter), t1);
        assertEq(routerFree0Before, 100e18, "Router has 100e18 token0 deposited");
        assertEq(routerFree1Before, 100e18, "Router has 100e18 token1 deposited");

        vm.warp(block.timestamp + 12);

        // Swap — JIT should inject virtual liquidity from SharedPool positions
        _doSwap(true, -1e18);

        // JIT PnL changes router's SharedPool freeBalance
        uint256 routerFree0After = sharedPool.freeBalance(address(tranchesRouter), t0);
        uint256 routerFree1After = sharedPool.freeBalance(address(tranchesRouter), t1);
        bool balancesChanged =
            (routerFree0After != routerFree0Before) || (routerFree1After != routerFree1Before);
        assertTrue(balancesChanged, "JIT PnL changed SharedPool balances");

        // Tranche fees accumulated via waterfall
        (,, uint256 sf, uint256 jf,,) = hook.getPoolStats(poolKey);
        assertGt(sf + jf, 0, "Tranche fees from swap");
        assertGe(sf, jf, "Senior >= Junior (waterfall)");

        console.log("=== JIT + Virtual Tranches E2E ===");
        console.log("Router free0:", routerFree0Before, "->", routerFree0After);
        console.log("Router free1:", routerFree1Before, "->", routerFree1After);
        console.log("Senior fees:", sf, "Junior fees:", jf);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 17: Multi-swaps accumulate fees for virtual tranche LPs
    // ═══════════════════════════════════════════════════════════════════

    function test_virtualTranchesMultiSwaps() public {
        _depositVirtualTranches(10e18, 50e18, 10e18, 50e18);

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 12);
            _doSwap(i % 2 == 0, -0.5e18);
        }

        // Pending fees for virtual LPs
        (uint256 ap0, uint256 ap1) = hook.pendingFees(alice, poolKey);
        (uint256 bp0, uint256 bp1) = hook.pendingFees(bob, poolKey);

        assertGt(ap0 + ap1, 0, "Alice (Senior) earned fees");
        assertGt(bp0 + bp1, 0, "Bob (Junior) earned fees");
        assertGe(ap0 + ap1, bp0 + bp1, "Senior >= Junior total fees");

        console.log("=== Virtual Tranches Multi-Swap ===");
        console.log("Alice (Senior):", ap0, ap1);
        console.log("Bob (Junior):", bp0, bp1);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Test 18: Full lifecycle — virtual deposit → swaps → claim → remove
    // ═══════════════════════════════════════════════════════════════════

    function test_virtualFullLifecycle() public {
        address t0 = Currency.unwrap(currency0);

        // 1. Virtual deposits via SharedPool
        _depositVirtualTranches(10e18, 50e18, 10e18, 50e18);

        // 2. Swaps generate JIT PnL + tranche fees
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 12);
            _doSwap(i % 2 == 0, -0.5e18);
        }

        // 3. Advance past MIN_BLOCKS_LOCK before claiming (Fix #3: claimFees now has block lock)
        vm.roll(block.number + 101);

        // Alice claims fees
        vm.prank(alice);
        hook.claimFees(poolKey);
        uint256 c0 = hook.claimableBalance(alice, currency0);
        uint256 c1 = hook.claimableBalance(alice, currency1);
        assertGt(c0 + c1, 0, "Alice has claimable fees");

        // 4. Alice withdraws fees
        if (c0 > 0) {
            uint256 balBefore = TestToken(t0).balanceOf(alice);
            vm.prank(alice);
            hook.withdrawFees(currency0);
            assertEq(TestToken(t0).balanceOf(alice) - balBefore, c0, "Fees withdrawn");
        }

        // 5. Advance blocks, then Alice removes liquidity
        vm.roll(block.number + 101);
        uint256 aliceBal0Before = TestToken(t0).balanceOf(alice);
        vm.prank(alice);
        tranchesRouter.removeLiquidity(poolKey, -120, 120, 50e18, 50e18);

        uint256 aliceRecovered = TestToken(t0).balanceOf(alice) - aliceBal0Before;
        assertGt(aliceRecovered, 0, "Alice recovered tokens");

        // 6. Verify final state
        (uint256 ts, uint256 tj, uint256 sf, uint256 jf,,) = hook.getPoolStats(poolKey);
        assertEq(ts, 0, "Alice removed");
        assertEq(tj, 10e18, "Bob still in");
        assertGt(sf + jf, 0, "Fees were distributed");

        console.log("=== Virtual Full Lifecycle ===");
        console.log("Alice fees claimed:", c0, c1);
        console.log("Alice tokens recovered:", aliceRecovered);
        console.log("Total fees: Senior", sf, "Junior", jf);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _mintTokens(address to, uint256 amt) internal {
        TestToken(Currency.unwrap(currency0)).mint(to, amt);
        TestToken(Currency.unwrap(currency1)).mint(to, amt);
    }

    function _approveAll(address) internal {
        TestToken t0 = TestToken(Currency.unwrap(currency0));
        TestToken t1 = TestToken(Currency.unwrap(currency1));
        address[4] memory targets = [address(swapRouter), address(liqRouter), address(tranchesRouter), address(manager)];
        for (uint256 i = 0; i < targets.length; i++) {
            t0.approve(targets[i], type(uint256).max);
            t1.approve(targets[i], type(uint256).max);
        }
    }

    function _approveAllAs(address user) internal {
        vm.startPrank(user);
        TestToken t0 = TestToken(Currency.unwrap(currency0));
        TestToken t1 = TestToken(Currency.unwrap(currency1));
        address[5] memory targets =
            [address(swapRouter), address(liqRouter), address(tranchesRouter), address(manager), address(sharedPool)];
        for (uint256 i = 0; i < targets.length; i++) {
            t0.approve(targets[i], type(uint256).max);
            t1.approve(targets[i], type(uint256).max);
        }
        vm.stopPrank();
    }

    function _depositTranches(int256 sAmt, int256 jAmt) internal {
        vm.prank(alice);
        tranchesRouter.addLiquidityV4(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: sAmt, salt: bytes32(0)}),
            TranchesHook.Tranche.SENIOR
        );
        vm.prank(bob);
        tranchesRouter.addLiquidityV4(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: jAmt, salt: bytes32(0)}),
            TranchesHook.Tranche.JUNIOR
        );
    }

    /// @dev Virtual deposit helper: Alice Senior (-120/120), Bob Junior (-240/240)
    ///      Uses different tick ranges to avoid SharedPool duplicate position for same user (router)
    function _depositVirtualTranches(uint128 liq, uint256 amt0, uint128 liq2, uint256 amt1) internal {
        vm.prank(alice);
        tranchesRouter.addLiquidity(
            poolKey, -120, 120, liq, amt0, amt0, TranchesHook.Tranche.SENIOR
        );
        vm.prank(bob);
        tranchesRouter.addLiquidity(
            poolKey, -240, 240, liq2, amt1, amt1, TranchesHook.Tranche.JUNIOR
        );
    }

    function _setupJIT(address provider, uint256 a0, uint256 a1) internal {
        address t0 = Currency.unwrap(currency0);
        address t1 = Currency.unwrap(currency1);
        vm.startPrank(provider);
        sharedPool.deposit(t0, a0, provider);
        sharedPool.deposit(t1, a1, provider);
        sharedPool.addPosition(poolKey, -120, 120, 20e18, a0, a1, provider);
        vm.stopPrank();
    }

    function _doSwap(bool zeroForOne, int256 amount) internal {
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        swapRouter.swap(poolKey, SwapParams({zeroForOne: zeroForOne, amountSpecified: amount, sqrtPriceLimitX96: limit}));
    }
}
