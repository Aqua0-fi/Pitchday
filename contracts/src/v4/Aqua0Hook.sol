// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/types/BeforeSwapDelta.sol";
import {
    ModifyLiquidityParams,
    SwapParams
} from "@uniswap/v4-core/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SharedLiquidityPool} from "./SharedLiquidityPool.sol";

// Import the new Aqua0 base hook
import {Aqua0BaseHook} from "./Aqua0BaseHook.sol";

/// @title Aqua0Hook (Default Implementation)
/// @author Aqua0 Team
/// @notice Uniswap V4 hook that provides just-in-time (JIT) shared liquidity to pools.
///         This implementation inherits from Aqua0BaseHook to demonstrate how third-party
///         hook developers can easily integrate Aqua0 functionality into their own hooks.
///
///   Hook address must have bits 7 (BEFORE_SWAP) and 6 (AFTER_SWAP) set in the lower 14 bits.
///   Required address pattern: ...xx xx00 = 0x...C0 in the lowest byte.
///
///   IMPORTANT: This hook uses CREATE2 + salt mining to get a valid hook address.
///   See script/MineAndDeploy.s.sol.
contract Aqua0Hook is IHooks, Ownable, Aqua0BaseHook {
    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(
        IPoolManager _poolManager,
        SharedLiquidityPool _sharedPool
    ) Ownable(msg.sender) Aqua0BaseHook(_poolManager, _sharedPool) {}

    // ─── Fallback ─────────────────────────────────────────────────────────────

    /// @notice Allows the hook to receive ETH when settling native tokens
    receive() external payable {}

    // ─── IHooks: Initialization ───────────────────────────────────────────────

    function getHookPermissions()
        public
        pure
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // Aqua0 Needs beforeSwap to ADD JIT liquidity
                afterSwap: true, // Aqua0 Needs afterSwap to REMOVE JIT and SETTLE
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata,
        uint160
    ) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24
    ) external pure override returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (
            IHooks.afterAddLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (
            IHooks.afterRemoveLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    function beforeDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IHooks.afterDonate.selector;
    }

    // ─── IHooks: Core Swap Routing ────────────────────────────────────────────

    /// @notice Called by PoolManager before a swap.
    function beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    )
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // 1. Dev Experience: Inject Aqua0 Virtual Liquidity
        _addVirtualLiquidity(key);

        // 2. Perform any custom third-party hook logic here!
        // ... (e.g. KYC, fee logic, dynamic fees, limit orders)

        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    /// @notice Called by PoolManager after a swap.
    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        // 1. Perform any custom third-party hook logic here!
        // ... (e.g. MEV capture, fee distribution)

        // 2. Dev Experience: Remove Virtual Liquidity & Settle
        (bool hasJIT, ) = _removeVirtualLiquidity(key);
        if (hasJIT) {
            _settleVirtualLiquidityDeltas(key);
        }

        return (IHooks.afterSwap.selector, 0);
    }
}
