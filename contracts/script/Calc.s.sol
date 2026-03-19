// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

contract Calc is Script {
    function run() external pure {
        // ETH/USDC
        // 1 ETH = 1978.16 USDC
        uint160 sqrtPriceX96_1 = 3523792214202267345698265497600;
        int24 tick1 = TickMath.getTickAtSqrtPrice(sqrtPriceX96_1);
        console2.log("ETH/USDC Tick:", tick1);
        uint128 liq1 = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtPriceAtTick(-887220),
            TickMath.getSqrtPriceAtTick(887220),
            sqrtPriceX96_1,
            0.1 ether,
            197.8 ether
        );
        console2.log("ETH/USDC Liq Delta:", liq1);

        // USDC/WBTC
        // 1 WBTC = 67848.1 USDC -> 1 USDC = 0.0000147388 WBTC
        uint160 sqrtPriceX96_2 = 304166050470486642314444800;
        int24 tick2 = TickMath.getTickAtSqrtPrice(sqrtPriceX96_2);
        console2.log("USDC/WBTC Tick:", tick2);
        uint128 liq2 = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtPriceAtTick(-887220),
            TickMath.getSqrtPriceAtTick(887220),
            sqrtPriceX96_2,
            2000 ether,
            0.02947 ether
        );
        console2.log("USDC/WBTC Liq Delta:", liq2);
    }
}
