// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice 5 demo swaps across all 4 pools (round-robin).
///         Run: forge script script/DemoSwaps.s.sol:DemoSwaps \
///              --rpc-url https://sepolia.unichain.org \
///              --private-key $DEPLOYER_PRIVATE_KEY --broadcast
contract DemoSwaps is Script {
    // ─── Addresses ───────────────────────────────────────────────────────────────
    address constant MUSDC  = 0x73c56ddD816e356387Caf740c804bb9D379BE47E;
    address constant MWETH  = 0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad;
    address constant ROUTER = 0x84175aA7EfD2805Ff8Dc2CF49EC3990b50daf3a1; // PoolSwapTest

    // Hooks (4 pools)
    address constant HOOK_CONSERVATIVE = 0x16326eCA33f5B28e3D572Ed38B066919E8E555C5;
    address constant HOOK_STANDARD     = 0x8E104beAC6dA7351B00b36E9f2B248F2BfD595c5;
    address constant HOOK_AGGRESSIVE   = 0xA6a0b93092aF21cBAB5f69C243f0dA2cF466D5c5;
    address constant HOOK_TRADITIONAL  = 0xAf99B4dBAeEfAeC6AbCb1018290ea705B3C895c5;

    // sqrtPriceLimitX96 boundaries
    uint160 constant MIN_SQRT_PRICE = 4295128740;
    uint160 constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970341;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // Approve router for both tokens (infinite)
        IERC20(MUSDC).approve(ROUTER, type(uint256).max);
        IERC20(MWETH).approve(ROUTER, type(uint256).max);

        console.log("=== 5 Demo Swaps (round-robin across 4 pools) ===");
        console.log("Deployer:", deployer);

        // ── Swap 1: Conservative (0.05%) — 500 mUSDC → mWETH ──
        _swap(
            HOOK_CONSERVATIVE, 500, 10,
            true,        // zeroForOne (mUSDC → mWETH)
            500e18,      // 500 mUSDC
            "Swap 1: 500 mUSDC -> mWETH via Conservative (0.05%)"
        );

        // ── Swap 2: Standard (0.30%) — 0.1 mWETH → mUSDC ──
        _swap(
            HOOK_STANDARD, 3000, 60,
            false,       // oneForZero (mWETH → mUSDC)
            0.1e18,      // 0.1 mWETH
            "Swap 2: 0.1 mWETH -> mUSDC via Standard (0.30%)"
        );

        // ── Swap 3: Aggressive (1.00%) — 1000 mUSDC → mWETH ──
        _swap(
            HOOK_AGGRESSIVE, 10000, 200,
            true,        // zeroForOne (mUSDC → mWETH)
            1000e18,     // 1000 mUSDC
            "Swap 3: 1000 mUSDC -> mWETH via Aggressive (1.00%)"
        );

        // ── Swap 4: Traditional (0.30%) — 0.05 mWETH → mUSDC ──
        _swap(
            HOOK_TRADITIONAL, 3000, 60,
            false,       // oneForZero (mWETH → mUSDC)
            0.05e18,     // 0.05 mWETH
            "Swap 4: 0.05 mWETH -> mUSDC via Traditional (0.30%)"
        );

        // ── Swap 5: Conservative (0.05%) — 200 mUSDC → mWETH ──
        _swap(
            HOOK_CONSERVATIVE, 500, 10,
            true,        // zeroForOne (mUSDC → mWETH)
            200e18,      // 200 mUSDC
            "Swap 5: 200 mUSDC -> mWETH via Conservative (0.05%)"
        );

        vm.stopBroadcast();
        console.log("=== All 5 swaps complete ===");
    }

    function _swap(
        address hook,
        uint24 fee,
        int24 tickSpacing,
        bool zeroForOne,
        uint256 amountIn,
        string memory label
    ) internal {
        console.log(label);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(MUSDC),
            currency1: Currency.wrap(MWETH),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });

        PoolSwapTest(ROUTER).swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountIn), // negative = exact input
                sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE : MAX_SQRT_PRICE
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
    }
}
