// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core-test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/libraries/TransientStateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TranchesHook} from "./TranchesHook.sol";
import {SharedLiquidityPool} from "../SharedLiquidityPool.sol";

/// @title TranchesRouter
/// @notice Router for TrancheFi tranche operations via Aqua0 SharedLiquidityPool.
///
///         Virtual deposit flow (LP calls directly):
///           1. LP approves this router for both tokens
///           2. LP calls addLiquidity() — router handles deposit into SharedPool,
///              creates virtual position, and registers tranche on the hook.
///
///         Virtual withdrawal flow:
///           1. LP calls removeLiquidity() — router unregisters tranche, removes
///              SharedPool position, withdraws tokens back to LP.
///
///         Legacy V4 deposit path preserved via addLiquidityV4 for backward compatibility.
contract TranchesRouter is IUnlockCallback {
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    IPoolManager public immutable manager;
    TranchesHook public immutable hook;
    SharedLiquidityPool public immutable sharedPool;

    /// @dev Per-LP deposited amounts: lp => poolId => token => amount
    ///      Scoped by pool to prevent cross-pool balance commingling.
    mapping(address => mapping(bytes32 => mapping(address => uint256))) public lpDeposits;

    // Legacy callback struct (for V4 direct path)
    struct CallbackData {
        address sender;
        PoolKey key;
        ModifyLiquidityParams params;
        bytes hookData;
    }

    constructor(IPoolManager _manager, TranchesHook _hook, SharedLiquidityPool _sharedPool) {
        manager = _manager;
        hook = _hook;
        sharedPool = _sharedPool;
    }

    // ============ Virtual Deposit (SharedPool path) ============

    /// @notice Deposit tokens into Aqua0 SharedPool, create virtual position, register tranche.
    ///         LP must approve this router for both pool tokens before calling.
    /// @param key          The V4 pool key
    /// @param tickLower    Lower tick for the virtual position
    /// @param tickUpper    Upper tick for the virtual position
    /// @param liquidity    Virtual liquidity units to allocate
    /// @param amount0      Amount of token0 to deposit as backing
    /// @param amount1      Amount of token1 to deposit as backing
    /// @param tranche      SENIOR or JUNIOR
    function addLiquidity(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        TranchesHook.Tranche tranche
    ) external {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        // 1. Pull tokens from LP to this router (use balance diff for fee-on-transfer safety)
        uint256 received0 = 0;
        uint256 received1 = 0;
        if (amount0 > 0) {
            uint256 bal0Before = IERC20(token0).balanceOf(address(this));
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
            received0 = IERC20(token0).balanceOf(address(this)) - bal0Before;
        }
        if (amount1 > 0) {
            uint256 bal1Before = IERC20(token1).balanceOf(address(this));
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
            received1 = IERC20(token1).balanceOf(address(this)) - bal1Before;
        }

        // 2. Register tranche on hook FIRST (reverts here are safe — no SharedPool state changed)
        hook.recordVirtualDeposit(msg.sender, key, tranche, uint256(liquidity));

        // 3. Approve SharedPool and deposit (credits router's freeBalance)
        if (received0 > 0) {
            IERC20(token0).forceApprove(address(sharedPool), received0);
            sharedPool.deposit(token0, received0, address(this));
        }
        if (received1 > 0) {
            IERC20(token1).forceApprove(address(sharedPool), received1);
            sharedPool.deposit(token1, received1, address(this));
        }

        // 4. Create virtual position in SharedPool (owned by router)
        sharedPool.addPosition(key, tickLower, tickUpper, liquidity, received0, received1, address(this));

        // 5. Track per-LP deposits for safe withdrawal (scoped by pool)
        bytes32 pid = keccak256(abi.encode(key));
        if (received0 > 0) lpDeposits[msg.sender][pid][token0] += received0;
        if (received1 > 0) lpDeposits[msg.sender][pid][token1] += received1;
    }

    /// @notice Remove virtual position from SharedPool and withdraw tokens back to LP.
    /// @param key              The V4 pool key
    /// @param tickLower        Lower tick of the position to remove
    /// @param tickUpper        Upper tick of the position to remove
    /// @param amount0Initial   Initial token0 backing (from addLiquidity)
    /// @param amount1Initial   Initial token1 backing (from addLiquidity)
    function removeLiquidity(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Initial,
        uint256 amount1Initial
    ) external {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        // 1. Unregister tranche on hook (auto-claims pending fees)
        hook.recordVirtualWithdrawal(msg.sender, key, 0); // 0 = full position

        // 2. Remove virtual position from SharedPool
        //    Try user-owned position first (addLiquidityFromSharedPool path),
        //    fall back to router-owned (legacy addLiquidity path)
        sharedPool.removePosition(key, tickLower, tickUpper, msg.sender);

        // 3. Clear LP deposit tracking
        bytes32 pid = keccak256(abi.encode(key));
        lpDeposits[msg.sender][pid][token0] = 0;
        lpDeposits[msg.sender][pid][token1] = 0;
    }

    // ============ Virtual Deposit from SharedPool (Aqua0 flow) ============

    /// @notice Amplify capital from user's SharedPool account into a specific pool.
    ///         Pure virtual — no tokens move. The same freeBalance backs multiple pools
    ///         simultaneously (Aqua shared liquidity model).
    ///         No token approval needed, single signature.
    /// @param key          The V4 pool key (must match this router's hook)
    /// @param tickLower    Lower tick for the virtual position
    /// @param tickUpper    Upper tick for the virtual position
    /// @param liquidity    Virtual liquidity units to allocate
    /// @param amount0      Amount of token0 to reference as backing
    /// @param amount1      Amount of token1 to reference as backing
    /// @param tranche      SENIOR or JUNIOR
    function addLiquidityFromSharedPool(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        TranchesHook.Tranche tranche
    ) external {
        // 1. Register tranche on hook
        hook.recordVirtualDeposit(msg.sender, key, tranche, uint256(liquidity));

        // 2. Create virtual position on user's freeBalance (checks balance but does NOT lock/move tokens)
        //    This is the Aqua model: same capital backs multiple pools simultaneously.
        sharedPool.addPosition(key, tickLower, tickUpper, liquidity, amount0, amount1, msg.sender);

        // 3. Track per-LP deposits for withdrawal accounting (scoped by pool)
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        bytes32 pid = keccak256(abi.encode(key));
        if (amount0 > 0) lpDeposits[msg.sender][pid][token0] += amount0;
        if (amount1 > 0) lpDeposits[msg.sender][pid][token1] += amount1;
    }

    // ============ Legacy V4 Direct Path (backward compat) ============

    /// @notice Legacy: atomically register and add real V4 liquidity
    function addLiquidityV4(PoolKey memory key, ModifyLiquidityParams memory params, TranchesHook.Tranche tranche)
        external
        returns (BalanceDelta delta)
    {
        hook.registerDepositFor(msg.sender, tranche);
        bytes memory hookData = abi.encode(msg.sender, tranche);
        delta =
            abi.decode(manager.unlock(abi.encode(CallbackData(msg.sender, key, params, hookData))), (BalanceDelta));
    }

    /// @notice IUnlockCallback: executes modifyLiquidity and settles tokens (legacy path)
    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager), "Not PoolManager");

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        (BalanceDelta delta,) = manager.modifyLiquidity(data.key, data.params, data.hookData);

        int256 delta0 = manager.currencyDelta(address(this), data.key.currency0);
        int256 delta1 = manager.currencyDelta(address(this), data.key.currency1);

        if (delta0 < 0) data.key.currency0.settle(manager, data.sender, uint256(-delta0), false);
        if (delta1 < 0) data.key.currency1.settle(manager, data.sender, uint256(-delta1), false);
        if (delta0 > 0) data.key.currency0.take(manager, data.sender, uint256(delta0), false);
        if (delta1 > 0) data.key.currency1.take(manager, data.sender, uint256(delta1), false);

        return abi.encode(delta);
    }
}
