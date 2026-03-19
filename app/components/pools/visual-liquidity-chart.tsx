"use client"

import React, { useMemo } from 'react'
import type { V4Pool } from '@/lib/v4-api'
import { parseUnits, formatUnits } from 'viem'

interface VisualLiquidityChartProps {
    pool: V4Pool
}

export function VisualLiquidityChart({ pool }: VisualLiquidityChartProps) {
    const { currentTick, currentPrice, tickSpacing, aggregatedRanges, realLiquidity, token0, token1 } = pool

    // Convert Tick to Price
    const tickToPrice = (tick: number) => {
        const rawPrice = Math.pow(1.0001, tick)
        const decimalAdjust = Math.pow(10, token0.decimals - token1.decimals)
        return rawPrice * decimalAdjust
    }

    const formatPrice = (price: number) => {
        if (price < 0.01) return price.toExponential(2)
        if (price > 1000) return price.toLocaleString('en-US', { maximumFractionDigits: 0 })
        return price.toLocaleString('en-US', { maximumFractionDigits: 2 })
    }

    // Chart Dimensions
    const width = 1000 // Internal SVG coordinate system
    const height = 160
    const padding = { top: 20, right: 30, bottom: 40, left: 30 }
    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom

    // Process Data
    const chartData = useMemo(() => {
        const fallbackMinTick = Math.floor(((currentTick || 0) - (tickSpacing * 15)) / tickSpacing) * tickSpacing;
        const fallbackMaxTick = Math.floor(((currentTick || 0) + (tickSpacing * 15)) / tickSpacing) * tickSpacing;

        const virtualMin = aggregatedRanges?.length ? Math.min(...aggregatedRanges.map(r => r.tickLower)) : Infinity;
        const virtualMax = aggregatedRanges?.length ? Math.max(...aggregatedRanges.map(r => r.tickUpper)) : -Infinity;

        const displayMinTick = Math.min(fallbackMinTick, virtualMin === Infinity ? fallbackMinTick : virtualMin);
        const displayMaxTick = Math.max(fallbackMaxTick, virtualMax === -Infinity ? fallbackMaxTick : virtualMax);

        const realLiq = (!realLiquidity || realLiquidity === "0") ? 0 : Number(formatUnits(BigInt(realLiquidity), 18));

        const bars = [];
        for (let tick = displayMinTick; tick <= displayMaxTick; tick += tickSpacing) {
            const chunkTickUpper = tick + tickSpacing;
            const priceLower = tickToPrice(tick);
            const priceUpper = tickToPrice(chunkTickUpper);

            let virtualLiq = 0;
            if (aggregatedRanges) {
                for (const range of aggregatedRanges) {
                    if (tick >= range.tickLower && tick < range.tickUpper) {
                        virtualLiq += Number(formatUnits(BigInt(range.totalLiquidity), 18));
                    }
                }
            }

            bars.push({
                tickLower: tick,
                tickUpper: chunkTickUpper,
                priceLower: priceLower,
                priceUpper: priceUpper,
                virtualLiquidity: virtualLiq,
                realLiquidity: realLiq,
                totalLiquidity: virtualLiq + realLiq,
                midTick: (tick + chunkTickUpper) / 2
            });
        }
        return bars;
    }, [aggregatedRanges, currentTick, tickSpacing, realLiquidity, token0.decimals, token1.decimals])

    const totalCalculatedLiquidity = chartData.reduce((acc, bar) => acc + bar.totalLiquidity, 0);

    if (totalCalculatedLiquidity === 0) {
        return (
            <div className="flex h-40 w-full items-center justify-center rounded-xl border border-dashed border-border/50 bg-secondary/10">
                <span className="text-sm text-muted-foreground">No liquidity in this pool yet</span>
            </div>
        )
    }

    // Calculate scales
    const minTick = chartData.length > 0 ? chartData[0].tickLower : (currentTick || 0) - tickSpacing * 15;
    const maxTick = chartData.length > 0 ? chartData[chartData.length - 1].tickUpper : (currentTick || 0) + tickSpacing * 15;

    // Add some padding to domain
    const tickDomainRange = Math.max(maxTick - minTick, tickSpacing * 10)
    const domainMin = minTick - (tickDomainRange * 0.05)
    const domainMax = maxTick + (tickDomainRange * 0.05)

    const maxLiquidity = Math.max(...chartData.map(d => d.totalLiquidity), 1)

    // Scale helpers
    const xScale = (tick: number) => {
        return padding.left + ((tick - domainMin) / (domainMax - domainMin)) * chartWidth
    }

    const yScale = (liquidity: number) => {
        return height - padding.bottom - ((liquidity / maxLiquidity) * chartHeight)
    }

    return (
        <div className="relative w-full overflow-hidden rounded-xl border border-border/50 bg-black/40 p-4">

            <svg viewBox={`0 0 ${width} ${height}`} className="h-full w-full overflow-visible" preserveAspectRatio="none">
                {/* Background Grid */}
                <line x1={padding.left} y1={height - padding.bottom} x2={width - padding.right} y2={height - padding.bottom} stroke="currentColor" className="text-border" strokeWidth="1" />

                {/* Current Price Line */}
                {currentTick !== 0 && (
                    <g transform={`translate(${xScale(currentTick)}, 0)`}>
                        <line x1="0" y1={padding.top} x2="0" y2={height - padding.bottom} stroke="#10b981" strokeWidth="2" strokeDasharray="4 4" />
                        <text x="0" y={padding.top - 5} fill="#10b981" fontSize="12" textAnchor="middle" className="font-mono">Current</text>
                    </g>
                )}

                {/* Liquidity Bars (Real and Virtual Stacked) */}
                {chartData.map((bar, i) => {
                    if (bar.totalLiquidity === 0) return null;

                    const x1 = xScale(bar.tickLower)
                    const x2 = xScale(bar.tickUpper)
                    const barWidth = Math.max(x2 - x1 - 2, 1) // Provide a 2px gap
                    const realY = yScale(bar.realLiquidity)
                    const virtualHeight = Math.max(yScale(bar.realLiquidity) - yScale(bar.totalLiquidity), 0)
                    const realHeight = Math.max(height - padding.bottom - realY, 0)

                    return (
                        <g key={i} className="group">
                            {/* Real Liquidity Bar */}
                            {bar.realLiquidity > 0 && (
                                <rect
                                    x={x1 + 1}
                                    y={realY}
                                    width={barWidth}
                                    height={realHeight}
                                    fill="url(#real-gradient)"
                                    stroke="#ec4899"
                                    strokeWidth="1"
                                    className="transition-all group-hover:opacity-80 cursor-pointer opacity-80"
                                />
                            )}

                            {/* Virtual Liquidity Bar (Stacked on top of Real) */}
                            {bar.virtualLiquidity > 0 && (
                                <rect
                                    x={x1 + 1}
                                    y={yScale(bar.totalLiquidity)}
                                    width={barWidth}
                                    height={virtualHeight}
                                    fill="url(#virtual-gradient)"
                                    stroke="#3b82f6"
                                    strokeWidth="1"
                                    className="transition-all group-hover:opacity-80 cursor-pointer"
                                />
                            )}

                            {/* Tick Label below axis */}
                            <text
                                x={x1 + barWidth / 2}
                                y={height - padding.bottom + 20}
                                fill="currentColor"
                                fontSize="10"
                                textAnchor="middle"
                                className="text-muted-foreground font-mono opacity-0 transition-opacity group-hover:opacity-100"
                            >
                                {`${formatPrice(bar.priceLower)} - ${formatPrice(bar.priceUpper)}`}
                            </text>

                            <text
                                x={x1 + barWidth / 2}
                                y={height - padding.bottom + 32}
                                fill="currentColor"
                                fontSize="9"
                                textAnchor="middle"
                                className="text-muted-foreground/50 opacity-0 transition-opacity group-hover:opacity-100"
                            >
                                Tick: {bar.tickLower}
                            </text>
                        </g>
                    )
                })}

                {/* Gradients */}
                <defs>
                    <linearGradient id="virtual-gradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#3b82f6" stopOpacity="0.8" />
                        <stop offset="100%" stopColor="#3b82f6" stopOpacity="0.2" />
                    </linearGradient>
                    <linearGradient id="real-gradient" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#ec4899" stopOpacity="0.3" />
                        <stop offset="100%" stopColor="#ec4899" stopOpacity="0.05" />
                    </linearGradient>
                </defs>
            </svg>

            {/* Legend */}
            <div className="absolute top-4 right-4 flex items-center gap-4 text-xs font-semibold">
                <div className="flex items-center gap-1.5">
                    <div className="w-3 h-3 rounded-sm border-2 border-pink-500 border-dashed bg-pink-500/20" />
                    <span className="text-muted-foreground">Real V4 Liquidity</span>
                </div>
                <div className="flex items-center gap-1.5">
                    <div className="w-3 h-3 rounded-sm border-2 border-blue-500 bg-blue-500/50" />
                    <span className="text-muted-foreground">Virtual JIT Liquidity</span>
                </div>
            </div>

        </div>
    )
}
