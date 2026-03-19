// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {PoolSwapTest} from "@uniswap/v4-core/test/PoolSwapTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DemoSwaps
/// @notice Executes 10 random swaps across all 4 TrancheFi pools for pitch demo.
///         Swaps alternate between zeroForOne and oneForZero to simulate real trading.
contract DemoSwaps is Script {
    // ─── Addresses ─────────────────────────────────────────────────────────────
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant MUSDC = 0x73c56ddD816e356387Caf740c804bb9D379BE47E;
    address constant MWETH = 0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad;

    // Pool hooks (from deployment)
    address constant HOOK_CONSERVATIVE = 0xFf349605984301b983D502E3999aA1F8BcBC95c5;
    address constant HOOK_STANDARD     = 0xc3B393BC673F580D4712DcEF0e6D7045FFe195c5;
    address constant HOOK_AGGRESSIVE   = 0x2a996Ce5e3E720743eE8c1c41edCB508f10AD5C5;
    address constant HOOK_TRADITIONAL  = 0xADd3CDE7F6584596A6ccf564703AEE8e959995c5;

    struct PoolInfo {
        string label;
        uint24 fee;
        int24 tickSpacing;
        address hook;
    }

    function run() external {
        uint256 deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        console.log("=== Demo Swaps ===");
        console.log("Deployer:", deployer);

        // Deploy a PoolSwapTest router
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOL_MANAGER));
        console.log("SwapRouter:", address(swapRouter));

        // Approve tokens for swap router
        IERC20(MUSDC).approve(address(swapRouter), type(uint256).max);
        IERC20(MWETH).approve(address(swapRouter), type(uint256).max);

        // Define pools
        PoolInfo[4] memory pools = [
            PoolInfo("Conservative (0.05%)", 500, 10, HOOK_CONSERVATIVE),
            PoolInfo("Standard (0.30%)", 3000, 60, HOOK_STANDARD),
            PoolInfo("Aggressive (1.00%)", 10000, 200, HOOK_AGGRESSIVE),
            PoolInfo("Traditional (0.30%)", 3000, 60, HOOK_TRADITIONAL)
        ];

        // 10 swaps: cycle through pools, alternate direction
        uint256 swapAmount = 0.1 ether; // 0.1 mWETH per swap (or 200 mUSDC)

        for (uint256 i = 0; i < 10; i++) {
            uint256 poolIdx = i % 4; // Rotate across all 4 pools
            bool zeroForOne = (i % 2 == 0); // Alternate direction

            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(MUSDC),
                currency1: Currency.wrap(MWETH),
                fee: pools[poolIdx].fee,
                tickSpacing: pools[poolIdx].tickSpacing,
                hooks: IHooks(pools[poolIdx].hook)
            });

            int256 amountSpecified = zeroForOne
                ? int256(200 ether) // 200 mUSDC → mWETH
                : int256(swapAmount); // 0.1 mWETH → mUSDC

            IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -amountSpecified, // negative = exact input
                sqrtPriceLimitX96: zeroForOne
                    ? 4295128739 + 1 // MIN_SQRT_PRICE + 1
                    : 1461446703485210103287273052203988822378723970342 - 1 // MAX_SQRT_PRICE - 1
            });

            PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });

            console.log("");
            console.log("--- Swap", i + 1, "---");
            console.log("  Pool:", pools[poolIdx].label);
            console.log("  Direction:", zeroForOne ? "mUSDC -> mWETH" : "mWETH -> mUSDC");

            swapRouter.swap(key, params, settings, "");

            console.log("  Done!");
        }

        console.log("");
        console.log("=== All 10 swaps complete ===");
        console.log("Check each pool's pendingFees to compare Aqua vs Traditional earnings");

        vm.stopBroadcast();
    }
}
