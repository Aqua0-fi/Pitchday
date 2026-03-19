// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {
    IUnlockCallback
} from "@uniswap/v4-core/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";
import {SharedLiquidityPool} from "./SharedLiquidityPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";

error QuoteExactInputResult(
    int256 totalAmountOut,
    int256 virtualDelta0,
    int256 virtualDelta1
);

contract Aqua0QuoteHelper is IUnlockCallback {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    IPoolManager public immutable poolManager;
    SharedLiquidityPool public immutable sharedPool;

    struct QuoteData {
        PoolKey key;
        bool zeroForOne;
        int256 amountSpecified;
    }

    uint160 constant MIN_PRICE_LIMIT = 4295128739 + 1;
    uint160 constant MAX_PRICE_LIMIT =
        1461446703485210103287273052203988822378723970342 - 1;

    constructor(IPoolManager _manager, SharedLiquidityPool _sharedPool) {
        poolManager = _manager;
        sharedPool = _sharedPool;
    }

    function quoteExactInput(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn
    ) external returns (int256, int256, int256) {
        QuoteData memory data = QuoteData({
            key: key,
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn) // Exact input is negative
        });

        // Trigger unlock; this will run unlockCallback and then revert intentionally.
        poolManager.unlock(abi.encode(data));

        return (0, 0, 0); // unreachable
    }

    function unlockCallback(
        bytes calldata rawData
    ) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Not poolManager");
        QuoteData memory data = abi.decode(rawData, (QuoteData));

        Currency currency0 = data.key.currency0;
        Currency currency1 = data.key.currency1;

        uint256 sharedBal0Before = _balanceOf(currency0, address(sharedPool));
        uint256 sharedBal1Before = _balanceOf(currency1, address(sharedPool));

        BalanceDelta delta = poolManager.swap(
            data.key,
            SwapParams({
                zeroForOne: data.zeroForOne,
                amountSpecified: data.amountSpecified,
                sqrtPriceLimitX96: data.zeroForOne
                    ? MIN_PRICE_LIMIT
                    : MAX_PRICE_LIMIT
            }),
            ""
        );

        uint256 sharedBal0After = _balanceOf(currency0, address(sharedPool));
        uint256 sharedBal1After = _balanceOf(currency1, address(sharedPool));

        int256 virtualDelta0 = int256(sharedBal0After) -
            int256(sharedBal0Before);
        int256 virtualDelta1 = int256(sharedBal1After) -
            int256(sharedBal1Before);

        // For exact input, amountSpecified < 0. delta.amount0() is negative (we pay), delta.amount1() is positive (we get).
        int256 totalAmountOut = data.zeroForOne
            ? delta.amount1()
            : delta.amount0();

        revert QuoteExactInputResult(
            totalAmountOut,
            virtualDelta0,
            virtualDelta1
        );
    }

    function _balanceOf(
        Currency currency,
        address target
    ) internal view returns (uint256) {
        if (currency.isAddressZero()) return target.balance;
        return IERC20(Currency.unwrap(currency)).balanceOf(target);
    }
}
