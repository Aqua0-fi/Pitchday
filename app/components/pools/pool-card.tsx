"use client"

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { TokenPairIcon } from '@/components/token-icon'
import type { V4Pool } from '@/lib/v4-api'
import { ArrowUpRight, TrendingUp, ShieldCheck } from 'lucide-react'
import { isTranchesHook, isTraditionalHook, isTrancheFiPool } from '@/lib/contracts'

interface PoolCardProps {
    pool: V4Pool
}

export function PoolCard({ pool }: PoolCardProps) {
    const router = useRouter()

    const handleSeeDetails = (e: React.MouseEvent) => {
        e.preventDefault()
        e.stopPropagation()
        router.push(`/pools/${pool.poolId}`)
    }

    // TokenPairIcon expects an array of { symbol, logo }
    // We don't have exact logo URLs from the V4 pools registry in MVP, so we fallback to assuming they match `/crypto/SYMBOL.png`
    const getLogo = (symbol: string) => {
        const cleanSymbol = symbol.replace(/^m/, '');
        if (cleanSymbol === 'WBTC') return '/crypto/BTC.png';
        if (cleanSymbol === 'WETH') return '/crypto/ETH.png';
        return `/crypto/${cleanSymbol}.png`;
    };

    const tokenPair = [
        { ...pool.token0, logo: getLogo(pool.token0.symbol) },
        { ...pool.token1, logo: getLogo(pool.token1.symbol) },
    ]

    return (
        <Card className="group relative flex h-full flex-col overflow-hidden border-border/50 bg-secondary/20 transition-all duration-300 hover:border-border hover:bg-secondary/40">
            <Link href={`/pools/${pool.poolId}`} className="absolute inset-0 z-10">
                <span className="sr-only">View pool details</span>
            </Link>

            <div className="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-300 group-hover:opacity-100" style={{ background: 'radial-gradient(ellipse at top left, #10b98106, transparent 70%)' }} />

            <CardContent className="relative flex-1 p-5">
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                        <TokenPairIcon tokens={tokenPair as any} size="lg" />
                        <div>
                            <p className="text-xs font-medium text-muted-foreground">
                                {isTrancheFiPool(pool.poolKey.hooks) ? 'TrancheFi x Aqua0' : 'Uniswap V4'}
                            </p>
                            <h3 className="text-base font-semibold">
                                {isTrancheFiPool(pool.poolKey.hooks)
                                    ? 'TrancheFi (Senior/Junior)'
                                    : `${pool.token0.symbol}/${pool.token1.symbol}`}
                            </h3>
                            <span className="inline-block mt-0.5 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-violet-500/10 text-violet-400">
                                Aqua0 Hook
                            </span>
                            {isTranchesHook(pool.poolKey.hooks) && (
                                <span className="inline-flex items-center gap-1 mt-0.5 ml-1 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-blue-500/10 text-blue-400">
                                    <ShieldCheck className="h-2.5 w-2.5" />
                                    TrancheFi
                                </span>
                            )}
                            {isTraditionalHook(pool.poolKey.hooks) && (
                                <span className="inline-flex items-center gap-1 mt-0.5 ml-1 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-red-500/10 text-red-400">
                                    No Aqua
                                </span>
                            )}
                            {isTranchesHook(pool.poolKey.hooks) && !isTraditionalHook(pool.poolKey.hooks) && (
                                <span className="inline-flex items-center gap-1 mt-0.5 ml-1 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-emerald-500/10 text-emerald-400">
                                    Shared Liquidity
                                </span>
                            )}
                        </div>
                    </div>
                    <div className="flex flex-col items-end">
                        <div className="flex items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-1">
                            <TrendingUp className="h-3 w-3 text-emerald-400" />
                            <span className="text-sm font-bold text-emerald-400">JIT Liq</span>
                        </div>
                    </div>
                </div>

                <div className="mt-5 grid grid-cols-2 gap-3">
                    <div className="rounded-lg bg-white/[0.03] p-3">
                        <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Swap Fee</p>
                        <p className="mt-1 text-lg font-bold tabular-nums">{(pool.fee / 10000).toFixed(2)}%</p>
                    </div>
                    <div className="rounded-lg bg-white/[0.03] p-3">
                        <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Current Price</p>
                        <p className="mt-1 text-lg font-bold tabular-nums">{pool.currentPrice.toPrecision(5)}</p>
                    </div>
                </div>

                <Button
                    className="relative z-20 mt-4 w-full gap-2 border-border/50 bg-white/[0.04] text-foreground transition-all duration-200 hover:bg-white/[0.08] hover:gap-3"
                    variant="outline"
                    onClick={handleSeeDetails}
                >
                    See Details
                    <ArrowUpRight className="h-4 w-4 transition-transform duration-200 group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                </Button>
            </CardContent>
        </Card>
    )
}

export function PoolCardSkeleton() {
    return (
        <Card className="flex h-full flex-col overflow-hidden border-border/50 bg-secondary/20">
            <CardContent className="flex-1 p-5">
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                        <div className="flex -space-x-2">
                            <div className="h-8 w-8 animate-pulse rounded-full bg-muted" />
                            <div className="h-8 w-8 animate-pulse rounded-full bg-muted" />
                        </div>
                        <div className="space-y-2">
                            <div className="h-4 w-28 animate-pulse rounded bg-muted" />
                            <div className="h-3 w-20 animate-pulse rounded bg-muted" />
                        </div>
                    </div>
                    <div className="h-7 w-16 animate-pulse rounded-full bg-muted" />
                </div>

                <div className="mt-5 grid grid-cols-2 gap-3">
                    {[1, 2].map((i) => (
                        <div key={i} className="rounded-lg bg-white/[0.03] p-3 space-y-2">
                            <div className="h-2.5 w-8 animate-pulse rounded bg-muted" />
                            <div className="h-6 w-14 animate-pulse rounded bg-muted" />
                        </div>
                    ))}
                </div>

                <div className="mt-4 h-10 w-full animate-pulse rounded-md bg-muted" />
            </CardContent>
        </Card>
    )
}
