// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
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
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAqua0BaseHookMarker} from "./IAqua0BaseHookMarker.sol";
import {SharedLiquidityPool} from "./SharedLiquidityPool.sol";
import {
    TransientStateLibrary
} from "@uniswap/v4-core/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";
import {console} from "forge-std/console.sol";

/// @title Aqua0BaseHook
/// @author Aqua0 Team
/// @notice Abstract contract that provides internal functions for custom Uniswap V4 hooks
///         to easily integrate Aqua0's internal JIT shared liquidity mechanism.
abstract contract Aqua0BaseHook is IAqua0BaseHookMarker {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using TransientStateLibrary for IPoolManager;
    using StateLibrary for IPoolManager;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice The Uniswap V4 PoolManager
    IPoolManager public immutable poolManager;

    /// @notice The Aqua0 shared liquidity pool (holds all user tokens)
    SharedLiquidityPool public immutable sharedPool;

    // ─── Events ──────────────────────────────────────────────────────────────

    event VirtualLiquidityAdded(
        PoolId indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );
    event VirtualLiquidityRemoved(
        PoolId indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );
    event NetDeltaSettled(
        address indexed token0,
        address indexed token1,
        int128 delta0,
        int128 delta1
    );

    // ─── Errors ──────────────────────────────────────────────────────────────

    error NotPoolManager();
    error HookNotApproved();

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(IPoolManager _poolManager, SharedLiquidityPool _sharedPool) {
        poolManager = _poolManager;
        sharedPool = _sharedPool;
    }

    // ─── ERC165 ──────────────────────────────────────────────────────────────

    /// @inheritdoc IAqua0BaseHookMarker
    function isAqua0BaseHook() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IAqua0BaseHookMarker).interfaceId;
    }

    // ─── Internal API for Custom Hooks ───────────────────────────────────────

    /// @notice Inject virtual JIT liquidity from Aqua0's shared pool.
    /// @dev Call this inside `beforeSwap` of your custom hook.
    /// @param key The pool key for the current swap
    function _addVirtualLiquidity(PoolKey calldata key) internal {
        PoolId poolId = key.toId();

        SharedLiquidityPool.RangeInfo[] memory ranges = sharedPool.preSwap(key);

        console.log("\n[Aqua0BaseHook] BEFORE SWAP");
        console.log("  Pool:       ", address(key.hooks));
        console.log("  JIT ranges: ", ranges.length);

        uint256 rangeCount = ranges.length;
        bytes32 ptrRangeCount = keccak256(abi.encode(poolId, "rangeCount"));
        assembly {
            tstore(ptrRangeCount, rangeCount)
        }

        for (uint256 i = 0; i < rangeCount; i++) {
            SharedLiquidityPool.RangeInfo memory r = ranges[i];

            console.log("  [+] Adding JIT liquidity");
            console.log("      tickLower:  ", r.tickLower);
            console.log("      tickUpper:  ", r.tickUpper);
            console.log("      liquidity:  ", r.totalLiquidity);

            (BalanceDelta callerDelta, ) = poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: r.tickLower,
                    tickUpper: r.tickUpper,
                    liquidityDelta: int256(uint256(r.totalLiquidity)),
                    salt: bytes32(0)
                }),
                ""
            );

            // Transiently store the exact mint cost
            bytes32 ptrMint = keccak256(abi.encode(poolId, "mintDelta", i));
            bytes32 ptrLower = keccak256(abi.encode(poolId, "tickLower", i));
            bytes32 ptrUpper = keccak256(abi.encode(poolId, "tickUpper", i));
            bytes32 ptrLiq = keccak256(abi.encode(poolId, "liquidity", i));

            int256 callerDeltaInt = BalanceDelta.unwrap(callerDelta);
            int256 tickLowerInt = int256(r.tickLower);
            int256 tickUpperInt = int256(r.tickUpper);
            uint256 liquidityUint = uint256(r.totalLiquidity);

            assembly {
                tstore(ptrMint, callerDeltaInt)
                tstore(ptrLower, tickLowerInt)
                tstore(ptrUpper, tickUpperInt)
                tstore(ptrLiq, liquidityUint)
            }

            emit VirtualLiquidityAdded(
                poolId,
                r.tickLower,
                r.tickUpper,
                r.totalLiquidity
            );
        }

        if (rangeCount == 0) {
            console.log(
                "  No JIT positions - swap routes through pool liquidity only"
            );
        }
    }

    /// @notice Remove the injected JIT liquidity.
    /// @dev Call this early inside `afterSwap` of your custom hook. Returns true if there were ranges to remove.
    /// @param key The pool key for the current swap
    /// @return hasJIT True if virtual liquidity was present and removed, false otherwise
    /// @return lpFee The dynamically active LP fee at the time of the swap
    function _removeVirtualLiquidity(
        PoolKey calldata key
    ) internal returns (bool hasJIT, uint24 lpFee) {
        PoolId poolId = key.toId();

        console.log("\n[Aqua0BaseHook] AFTER SWAP");

        uint256 rangeCount;
        bytes32 ptrRangeCount = keccak256(abi.encode(poolId, "rangeCount"));
        assembly {
            rangeCount := tload(ptrRangeCount)
        }

        if (rangeCount == 0) {
            console.log("  No JIT positions - nothing to remove/settle");
            return (false, 0);
        }

        SharedLiquidityPool.RangeInfo[]
            memory injectedRanges = new SharedLiquidityPool.RangeInfo[](
                rangeCount
            );
        BalanceDelta[] memory mintDeltas = new BalanceDelta[](rangeCount);
        BalanceDelta[] memory burnDeltas = new BalanceDelta[](rangeCount);

        for (uint256 i = 0; i < rangeCount; i++) {
            int24 tickLower;
            int24 tickUpper;
            uint128 totalLiquidity;
            BalanceDelta mintDelta;

            bytes32 ptrMint = keccak256(abi.encode(poolId, "mintDelta", i));
            bytes32 ptrLower = keccak256(abi.encode(poolId, "tickLower", i));
            bytes32 ptrUpper = keccak256(abi.encode(poolId, "tickUpper", i));
            bytes32 ptrLiq = keccak256(abi.encode(poolId, "liquidity", i));

            int256 callerDeltaInt;
            int256 tickLowerInt;
            int256 tickUpperInt;
            uint256 liquidityUint;

            // Read transiently stored data
            assembly {
                tickLowerInt := tload(ptrLower)
                tickUpperInt := tload(ptrUpper)
                liquidityUint := tload(ptrLiq)
                callerDeltaInt := tload(ptrMint)
            }

            tickLower = int24(tickLowerInt);
            tickUpper = int24(tickUpperInt);
            totalLiquidity = uint128(liquidityUint);
            mintDelta = BalanceDelta.wrap(callerDeltaInt);

            injectedRanges[i] = SharedLiquidityPool.RangeInfo({
                tickLower: tickLower,
                tickUpper: tickUpper,
                totalLiquidity: totalLiquidity
            });
            mintDeltas[i] = mintDelta;

            (BalanceDelta callerDelta, ) = poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(totalLiquidity)),
                    salt: bytes32(0)
                }),
                ""
            );

            burnDeltas[i] = callerDelta;

            emit VirtualLiquidityRemoved(
                poolId,
                tickLower,
                tickUpper,
                totalLiquidity
            );
            console.log("  [-] Removed JIT liquidity");
            console.log("      tickLower:", tickLower);
            console.log("      tickUpper:", tickUpper);
            console.log("      liquidity:", totalLiquidity);
        }

        // Read the pool's current active LP Fee (needed to isolate swap fees from principle shift)
        (, , , lpFee) = poolManager.getSlot0(poolId);

        // Accurately distribute exact PnL to overlapping users based on their scale
        sharedPool.postSwap(key, injectedRanges, mintDeltas, burnDeltas, lpFee);

        return (true, lpFee);
    }

    /// @notice Settle the net token deltas derived from Aqua0's virtual liquidity operations.
    /// @dev Call this inside `afterSwap` right before returning, but ONLY if `_removeVirtualLiquidity` returned true.
    /// @param key The pool key for the current swap
    function _settleVirtualLiquidityDeltas(PoolKey calldata key) internal {
        int128 netHook0 = int128(
            poolManager.currencyDelta(address(this), key.currency0)
        );
        int128 netHook1 = int128(
            poolManager.currencyDelta(address(this), key.currency1)
        );

        console.log("  Hook net deltas:");
        if (netHook0 < 0) {
            console.log("    currency0 owes PM:", uint128(-netHook0), "wei");
        } else {
            console.log(
                "    currency0 PM owes hook:",
                uint128(netHook0),
                "wei"
            );
        }
        if (netHook1 < 0) {
            console.log("    currency1 owes PM:", uint128(-netHook1), "wei");
        } else {
            console.log(
                "    currency1 PM owes hook:",
                uint128(netHook1),
                "wei"
            );
        }

        if (netHook0 == 0 && netHook1 == 0) return;

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        emit NetDeltaSettled(token0, token1, netHook0, netHook1);

        _settleCurrency(key.currency0, token0, netHook0);
        _settleCurrency(key.currency1, token1, netHook1);
    }

    /// @notice Settle an exact currency delta with the PoolManager and SharedPool
    function _settleCurrency(
        Currency currency,
        address token,
        int128 netAmount
    ) private {
        if (netAmount == 0) return;

        if (netAmount < 0) {
            // Hook owes PoolManager: pull tokens from SharedLiquidityPool -> send to PM -> settle
            uint256 owed = uint256(uint128(-netAmount));

            if (currency.isAddressZero()) {
                console.log("  [settle] Hook owes PM (ETH wei):", owed);
                console.log("    -> Pulling ETH from SharedLiquidityPool");
                sharedPool.settleSwapDelta(token, -int256(owed));
                console.log(
                    "    -> Sending ETH to PoolManager via settle{value}"
                );
                poolManager.settle{value: owed}();
            } else {
                console.log("  [settle] Hook owes PM (ERC20 wei):", owed);
                console.log("    -> token:", token);
                console.log("    -> Pulling ERC20 from SharedLiquidityPool");
                sharedPool.settleSwapDelta(token, -int256(owed));
                console.log(
                    "    -> Transferring ERC20 to PoolManager + settle"
                );
                poolManager.sync(currency);
                IERC20(token).safeTransfer(address(poolManager), owed);
                poolManager.settle();
            }
        } else {
            // PM owes hook: take tokens directly into SharedLiquidityPool
            uint256 earned = uint256(uint128(netAmount));
            if (currency.isAddressZero()) {
                console.log("  [settle] PM owes hook (ETH wei):", earned);
                console.log("    -> taking to SharedPool");
            } else {
                console.log("  [settle] PM owes hook (ERC20 wei):", earned);
                console.log("    -> token:", token);
                console.log("    -> taking to SharedPool");
            }
            poolManager.take(currency, address(sharedPool), earned);
        }
    }
}
