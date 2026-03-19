export const MIN_TICK = -887272;
export const MAX_TICK = 887272;

export function tickToPrice(tick: number, decimals0 = 18, decimals1 = 18): number {
    const price = Math.pow(1.0001, tick);
    const adjustedPrice = price * Math.pow(10, decimals0 - decimals1);
    return adjustedPrice;
}

export function priceToTick(price: number, tickSpacing: number, decimals0 = 18, decimals1 = 18): number {
    const adjustedPrice = price / Math.pow(10, decimals0 - decimals1);
    let tick = Math.log(adjustedPrice) / Math.log(1.0001);

    // Nearest valid tick
    tick = Math.round(tick / tickSpacing) * tickSpacing;

    if (tick < MIN_TICK) return Math.ceil(MIN_TICK / tickSpacing) * tickSpacing;
    if (tick > MAX_TICK) return Math.floor(MAX_TICK / tickSpacing) * tickSpacing;

    return tick;
}

export function formatPrice(price: number): string {
    if (price === 0) return '0';
    if (price < 0.000001) return price.toExponential(4);
    if (price < 1) return price.toPrecision(4);
    if (price > 1000) return price.toFixed(2);
    return price.toPrecision(6);
}

export const Q96 = BigInt("79228162514264337593543950336");

export function getSqrtRatioAtTick(tick: number): bigint {
    const price = Math.pow(1.0001, tick);
    // Number(Q96) = 7.922816251426433e28, fits in JS float accurately enough for frontend approximation
    return BigInt(Math.floor(Math.sqrt(price) * 7.922816251426433e28));
}

export function getLiquidityForAmount0(sqrtRatioAX96: bigint, sqrtRatioBX96: bigint, amount0: bigint): bigint {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        const temp = sqrtRatioAX96; sqrtRatioAX96 = sqrtRatioBX96; sqrtRatioBX96 = temp;
    }
    const intermediate = (sqrtRatioAX96 * sqrtRatioBX96) / Q96;
    if (sqrtRatioBX96 === sqrtRatioAX96) return BigInt(0);
    return (amount0 * intermediate) / (sqrtRatioBX96 - sqrtRatioAX96);
}

export function getLiquidityForAmount1(sqrtRatioAX96: bigint, sqrtRatioBX96: bigint, amount1: bigint): bigint {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        const temp = sqrtRatioAX96; sqrtRatioAX96 = sqrtRatioBX96; sqrtRatioBX96 = temp;
    }
    if (sqrtRatioBX96 === sqrtRatioAX96) return BigInt(0);
    return (amount1 * Q96) / (sqrtRatioBX96 - sqrtRatioAX96);
}

export function getLiquidityForAmounts(
    sqrtRatioX96: bigint,
    sqrtRatioAX96: bigint,
    sqrtRatioBX96: bigint,
    amount0: bigint,
    amount1: bigint
): bigint {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        const temp = sqrtRatioAX96; sqrtRatioAX96 = sqrtRatioBX96; sqrtRatioBX96 = temp;
    }

    if (sqrtRatioX96 <= sqrtRatioAX96) {
        return getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
    } else if (sqrtRatioX96 < sqrtRatioBX96) {
        const liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
        const liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);
        return liquidity0 < liquidity1 ? liquidity0 : liquidity1;
    } else {
        return getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
    }
}

export function getAmountsForLiquidity(
    sqrtRatioX96: bigint,
    sqrtRatioAX96: bigint,
    sqrtRatioBX96: bigint,
    liquidity: bigint
): [bigint, bigint] {
    if (sqrtRatioAX96 > sqrtRatioBX96) {
        const temp = sqrtRatioAX96; sqrtRatioAX96 = sqrtRatioBX96; sqrtRatioBX96 = temp;
    }
    let amount0 = BigInt(0);
    let amount1 = BigInt(0);

    if (sqrtRatioX96 <= sqrtRatioAX96) {
        amount0 = (liquidity * Q96 * (sqrtRatioBX96 - sqrtRatioAX96)) / (sqrtRatioBX96 * sqrtRatioAX96);
    } else if (sqrtRatioX96 < sqrtRatioBX96) {
        amount0 = (liquidity * Q96 * (sqrtRatioBX96 - sqrtRatioX96)) / (sqrtRatioBX96 * sqrtRatioX96);
        amount1 = (liquidity * (sqrtRatioX96 - sqrtRatioAX96)) / Q96;
    } else {
        amount1 = (liquidity * (sqrtRatioBX96 - sqrtRatioAX96)) / Q96;
    }
    return [amount0, amount1];
}
