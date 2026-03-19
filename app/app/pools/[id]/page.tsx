"use client"

import { useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { TokenPairIcon } from '@/components/token-icon'
import { LoadingSpinner } from '@/components/loading-spinner'
import { useV4Pools } from '@/hooks/use-v4-pools'
import { ArrowLeft, TrendingUp, Info, ExternalLink, ArrowDownUp, Loader2, Droplets } from 'lucide-react'
import { useWallet } from '@/contexts/wallet-context'
import { TranchesLiquidityModal } from '@/components/pools/tranches-liquidity-modal'
import { isTranchesHook, isTraditionalHook, TRANCHES_SHARED_POOL, TRANCHES_POOLS, TRANCHES_POOL_KEY, ERC20_ABI } from '@/lib/contracts'
import { useTranchesStats } from '@/hooks/use-tranches-stats'
import { useReadContracts, useAccount } from 'wagmi'
import { formatUnits } from 'viem'
import { RSCOracleSimulator } from '@/components/pools/rsc-oracle-simulator'

function fmt(val: bigint, decimals = 18, dp = 4): string {
    const str = formatUnits(val, decimals)
    const num = parseFloat(str)
    if (num === 0) return '0'
    if (num < 0.0001) return '<0.0001'
    return num.toLocaleString(undefined, { maximumFractionDigits: dp })
}

function usePoolTokenBalances(poolAddress: string | undefined) {
    const { data, isLoading } = useReadContracts({
        contracts: poolAddress ? [
            { address: TRANCHES_POOL_KEY.currency0, abi: ERC20_ABI, functionName: 'balanceOf', args: [poolAddress as `0x${string}`] },
            { address: TRANCHES_POOL_KEY.currency1, abi: ERC20_ABI, functionName: 'balanceOf', args: [poolAddress as `0x${string}`] },
        ] : [],
        query: { enabled: !!poolAddress, refetchInterval: 10_000 },
    })
    return {
        mUSDC: (data?.[0]?.result as bigint) ?? 0n,
        mWETH: (data?.[1]?.result as bigint) ?? 0n,
        isLoading,
    }
}

export default function PoolDetailPage() {
    const params = useParams()
    const router = useRouter()
    const poolId = params.id as string
    const { chainId } = useWallet()
    const activeChainId = chainId || Number(process.env.NEXT_PUBLIC_CHAIN_ID || 84532)

    const { data: pools, isLoading } = useV4Pools(activeChainId)
    const [isProvideModalOpen, setIsProvideModalOpen] = useState(false)

    if (isLoading) {
        return (
            <div className="flex min-h-[60vh] items-center justify-center">
                <LoadingSpinner size="lg" />
            </div>
        )
    }

    const pool = pools?.find((p) => p.poolId === poolId)

    if (!pool) {
        return (
            <div className="flex min-h-[60vh] flex-col items-center justify-center gap-4">
                <p className="text-muted-foreground">Pool not found on this chain</p>
                <Button variant="outline" onClick={() => router.push('/')}>
                    <ArrowLeft className="mr-2 h-4 w-4" />
                    Back to Pools
                </Button>
            </div>
        )
    }

    const getLogo = (symbol: string) => {
        const cleanSymbol = symbol.replace(/^m/, '')
        if (cleanSymbol === 'WBTC') return '/crypto/BTC.png'
        if (cleanSymbol === 'WETH') return '/crypto/ETH.png'
        return `/crypto/${cleanSymbol}.png`
    }

    const tokenPair = [
        { ...pool.token0, logo: getLogo(pool.token0.symbol) },
        { ...pool.token1, logo: getLogo(pool.token1.symbol) },
    ]

    const isAqua = isTranchesHook(pool.poolKey.hooks) && !isTraditionalHook(pool.poolKey.hooks)
    const isTraditional = isTraditionalHook(pool.poolKey.hooks)

    // Determine which SharedPool to read balances from
    const poolConfig = TRANCHES_POOLS.find(
        (p) => p.hook.toLowerCase() === pool.poolKey.hooks.toLowerCase()
    )
    const sharedPoolAddr = isTraditional && poolConfig && 'isolatedPool' in poolConfig
        ? (poolConfig as any).isolatedPool
        : TRANCHES_SHARED_POOL

    return (
        <div className="container mx-auto px-4 py-8 max-w-5xl">
            <Link
                href="/"
                className="mb-6 inline-flex items-center text-sm text-muted-foreground transition-colors hover:text-foreground"
            >
                <ArrowLeft className="mr-2 h-4 w-4" />
                Back to Pools
            </Link>

            {/* Header */}
            <div className="mb-8 flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
                <div className="flex items-center gap-4">
                    <TokenPairIcon tokens={tokenPair as any} size="lg" />
                    <div>
                        <div className="flex flex-wrap items-center gap-2">
                            <h1 className="text-2xl font-bold">{pool.token0.symbol}/{pool.token1.symbol}</h1>
                            <span className="px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-violet-500/10 text-violet-400">
                                {(pool.fee / 10000).toFixed(2)}% Fee
                            </span>
                            {isAqua && (
                                <span className="px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-emerald-500/10 text-emerald-400">
                                    Aqua0 Shared
                                </span>
                            )}
                            {isTraditional && (
                                <span className="px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-red-500/10 text-red-400">
                                    Traditional LP
                                </span>
                            )}
                        </div>
                        <p className="mt-1 text-sm text-muted-foreground">
                            Tick Spacing: {pool.tickSpacing} • Chain {activeChainId}
                        </p>
                    </div>
                </div>
                <div className="flex items-center gap-3">
                    {isTranchesHook(pool.poolKey.hooks) && (
                        <RSCOracleSimulator currentPrice={pool.currentPrice} />
                    )}
                    <Button size="lg" className="gap-2" onClick={() => setIsProvideModalOpen(true)}>
                        <Droplets className="h-4 w-4" />
                        Provide Liquidity
                    </Button>
                </div>
            </div>

            {/* Pool Stats */}
            <PoolStats pool={pool} sharedPoolAddr={sharedPoolAddr} isAqua={isAqua} />

            {/* Swap UI */}
            <div className="mb-8">
                <h2 className="text-xl font-bold mb-4">Swap</h2>
                <PoolSwapUI pool={pool} poolConfig={poolConfig} />
            </div>

            {/* How it works */}
            <div className="rounded-xl border border-border/50 bg-secondary/20 p-6 flex items-start gap-4">
                <Info className="h-6 w-6 text-emerald-400 mt-0.5 shrink-0" />
                <div>
                    {isAqua ? (
                        <>
                            <h3 className="text-lg font-semibold mb-2 text-emerald-400">Aqua0 Shared Liquidity</h3>
                            <p className="text-sm text-foreground/80">
                                This pool shares liquidity with other Aqua0 pools. Your deposit earns fees from swaps across ALL shared pools simultaneously — not just this one. Capital efficiency is maximized through just-in-time virtual positions.
                            </p>
                        </>
                    ) : (
                        <>
                            <h3 className="text-lg font-semibold mb-2 text-red-400">Traditional LP (Isolated)</h3>
                            <p className="text-sm text-foreground/80">
                                This pool has its own isolated liquidity. Your deposit only earns fees from swaps in this specific pool. Capital is locked here and cannot be shared with other pools.
                            </p>
                        </>
                    )}
                </div>
            </div>

            {isProvideModalOpen && (
                <TranchesLiquidityModal
                    open={isProvideModalOpen}
                    onOpenChange={setIsProvideModalOpen}
                    poolPrice={pool.currentPrice}
                />
            )}
        </div>
    )
}

// ─── Pool Stats Component ─────────────────────────────────────────────────────

function PoolStats({ pool, sharedPoolAddr, isAqua }: { pool: any; sharedPoolAddr: string; isAqua: boolean }) {
    const { mUSDC, mWETH, isLoading } = usePoolTokenBalances(sharedPoolAddr)

    return (
        <div className="mb-8 grid grid-cols-2 gap-3 md:grid-cols-4">
            <div className="rounded-xl border border-border/50 bg-secondary/20 p-4">
                <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Total mWETH</p>
                <p className="mt-1.5 text-2xl font-bold tabular-nums">
                    {isLoading ? '...' : fmt(mWETH)}
                </p>
            </div>
            <div className="rounded-xl border border-border/50 bg-secondary/20 p-4">
                <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Total mUSDC</p>
                <p className="mt-1.5 text-2xl font-bold tabular-nums">
                    {isLoading ? '...' : fmt(mUSDC)}
                </p>
            </div>
            <div className="rounded-xl border border-border/50 bg-secondary/20 p-4">
                <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Swap Fee</p>
                <p className="mt-1.5 text-2xl font-bold tabular-nums text-emerald-400">
                    {(pool.fee / 10000).toFixed(2)}%
                </p>
            </div>
            <div className="rounded-xl border border-border/50 bg-secondary/20 p-4">
                <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Liquidity Type</p>
                <p className={`mt-1.5 text-lg font-bold ${isAqua ? 'text-emerald-400' : 'text-red-400'}`}>
                    {isAqua ? 'Shared (Aqua0)' : 'Isolated'}
                </p>
            </div>
        </div>
    )
}

// ─── Swap UI Component ────────────────────────────────────────────────────────

function PoolSwapUI({ pool, poolConfig }: { pool: any; poolConfig: any }) {
    const { address } = useAccount()
    const [direction, setDirection] = useState<'buy' | 'sell'>('buy')
    const [amount, setAmount] = useState('')
    const [isSwapping, setIsSwapping] = useState(false)

    const inputToken = direction === 'buy' ? 'mUSDC' : 'mWETH'
    const outputToken = direction === 'buy' ? 'mWETH' : 'mUSDC'

    // Simple estimated output (1:1 pool price for demo)
    const poolPrice = pool.currentPrice > 0 ? pool.currentPrice : 1
    const estimatedOutput = amount
        ? direction === 'buy'
            ? (parseFloat(amount) * poolPrice).toFixed(4)
            : (parseFloat(amount) / poolPrice).toFixed(4)
        : '0'

    return (
        <div className="max-w-md">
            <div className="rounded-xl border border-border/50 bg-secondary/20 p-5 space-y-4">
                {/* Direction toggle */}
                <div className="flex items-center justify-between">
                    <span className="text-sm font-medium">{inputToken} → {outputToken}</span>
                    <button
                        onClick={() => setDirection(d => d === 'buy' ? 'sell' : 'buy')}
                        className="flex h-8 w-8 items-center justify-center rounded-lg bg-white/[0.04] hover:bg-white/[0.08] transition-colors"
                    >
                        <ArrowDownUp className="h-3.5 w-3.5 text-muted-foreground" />
                    </button>
                </div>

                {/* Input */}
                <div className="rounded-lg bg-white/[0.03] p-3">
                    <p className="text-[10px] uppercase tracking-wider text-muted-foreground mb-1.5">You pay</p>
                    <div className="flex items-center gap-3">
                        <Input
                            type="number"
                            placeholder="0.0"
                            value={amount}
                            onChange={(e) => setAmount(e.target.value)}
                            className="border-0 bg-transparent text-xl font-bold shadow-none focus-visible:ring-0 p-0 h-auto"
                            min="0"
                        />
                        <span className="shrink-0 rounded-lg bg-white/[0.06] px-3 py-1.5 text-xs font-bold text-muted-foreground">
                            {inputToken}
                        </span>
                    </div>
                </div>

                {/* Arrow */}
                <div className="flex justify-center">
                    <div className="flex h-8 w-8 items-center justify-center rounded-lg border border-border/50 bg-secondary/20">
                        <ArrowDownUp className="h-3.5 w-3.5 text-muted-foreground" />
                    </div>
                </div>

                {/* Output */}
                <div className="rounded-lg bg-white/[0.03] p-3">
                    <p className="text-[10px] uppercase tracking-wider text-muted-foreground mb-1.5">You receive (est.)</p>
                    <div className="flex items-center gap-3">
                        <p className="flex-1 text-xl font-bold text-muted-foreground">{estimatedOutput}</p>
                        <span className="shrink-0 rounded-lg bg-white/[0.06] px-3 py-1.5 text-xs font-bold text-muted-foreground">
                            {outputToken}
                        </span>
                    </div>
                </div>

                {/* Rate */}
                <div className="rounded-lg bg-white/[0.02] px-3 py-2 text-center">
                    <p className="text-xs text-muted-foreground">
                        1 mWETH ≈ <span className="text-foreground/80 font-mono">{poolPrice.toFixed(2)}</span> mUSDC
                    </p>
                </div>

                {/* Swap button */}
                <Button
                    disabled={!amount || parseFloat(amount) <= 0 || isSwapping || !address}
                    className="w-full gap-2"
                    size="lg"
                >
                    {isSwapping ? (
                        <>
                            <Loader2 className="h-4 w-4 animate-spin" />
                            Swapping...
                        </>
                    ) : !address ? (
                        'Connect Wallet'
                    ) : (
                        'Swap'
                    )}
                </Button>
            </div>
        </div>
    )
}
