"use client"

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { useWallet } from '@/contexts/wallet-context'
import { Wallet, TrendingUp } from 'lucide-react'
import Image from 'next/image'
import { RealLiquidityManager } from '@/components/dashboard/real-liquidity-manager'
import { useV4Pools } from '@/hooks/use-v4-pools'
import { useUserPositions } from '@/hooks/use-user-positions'
import { formatUnits } from 'viem'
import { useSharedBalances } from '@/hooks/use-shared-balances'


export default function DashboardPage() {
    const { isConnected, address, connect, chainId } = useWallet()
    const activeChainId = chainId || Number(process.env.NEXT_PUBLIC_CHAIN_ID || 84532)
    const { data: pools } = useV4Pools(activeChainId)
    const { data: userPositions, isLoading: isPositionsLoading } = useUserPositions(activeChainId)

    // Extract all unique tokens from all pools to check fees
    const tokenAddresses = Array.from(new Set(pools?.flatMap(p => [p.token0.address, p.token1.address]) || []))
    const { data: balances } = useSharedBalances(activeChainId, address || undefined, tokenAddresses)

    const totalEarnedFeesUsd = balances?.reduce((acc, bal) => {
        const token = pools?.flatMap(p => [p.token0, p.token1]).find(t => t.address.toLowerCase() === bal.token.toLowerCase())
        if (!token || !bal.earnedFees) return acc
        const amount = Number(formatUnits(BigInt(bal.earnedFees), token.decimals))
        const isETH = token.symbol.toLowerCase().includes('eth')
        return acc + (isETH ? amount * 2000 : amount)
    }, 0) || 0

    const getStatusBadge = (status: string) => {
        switch (status) {
            case 'completed':
            case 'active':
                return <Badge variant="outline" className="bg-green-500/10 text-green-500 border-green-500/20">Active</Badge>
            case 'pending':
                return <Badge variant="outline" className="bg-yellow-500/10 text-yellow-500 border-yellow-500/20">Pending</Badge>
        }
    }

    if (!isConnected) {
        return (
            <div className="min-h-screen">
                <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
                    <div className="flex flex-col items-center justify-center text-center">
                        <Image src="/icons/Account.png" alt="Account" width={64} height={64} className="h-16 w-16 mb-6" unoptimized />
                        <h1 className="text-2xl font-bold mb-2">Connect Your Wallet</h1>
                        <p className="text-muted-foreground mb-6 max-w-md">
                            Connect your wallet to view your V4 positions, uncollected fees, and history.
                        </p>
                        <Button onClick={connect} size="lg">
                            <Wallet className="mr-2 h-4 w-4" />
                            Log in
                        </Button>
                    </div>
                </div>
            </div>
        )
    }

    return (
        <div className="min-h-screen">
            <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
                {/* Header */}
                <div className="mb-8">
                    <h1 className="text-2xl font-bold">Liquidity Dashboard</h1>
                    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mt-1">
                        <div className="flex items-center gap-2">
                            <span className="h-2 w-2 rounded-full bg-emerald-500" />
                            <span className="text-sm text-muted-foreground">
                                {address ? `${address.slice(0, 6)}\u2026${address.slice(-4)}` : 'Connected'}
                            </span>
                        </div>
                        <span className="text-sm text-muted-foreground">Chain ID: {activeChainId}</span>
                    </div>
                </div>

                {/* Stats Cards */}
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 mb-8">
                    {[
                        { label: 'Virtual Positions', value: (userPositions?.length || 0).toString() },
                        { label: 'Uncollected Fees', value: `+$${totalEarnedFeesUsd.toFixed(2)}`, color: 'text-emerald-400' },
                        { label: 'Active JIT Pools', value: new Set(userPositions?.map(p => p.poolId)).size.toString() },
                        { label: 'Average APY', value: "N/A", color: 'text-emerald-400' }, // Placeholder MVP
                    ].map((stat) => (
                        <div
                            key={stat.label}
                            className="rounded-xl border border-border/50 bg-secondary/20 p-5"
                        >
                            <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{stat.label}</p>
                            <p className={`mt-2 text-2xl font-bold tabular-nums ${stat.color || ''}`}>{stat.value}</p>
                        </div>
                    ))}
                </div>

                {/* Real Liquidity Manager */}
                {pools && <RealLiquidityManager pools={pools} />}

                {/* Active Positions & Fees */}
                <Card className="mb-8">
                    <CardHeader>
                        <CardTitle>Your V4 Pool Positions & Fees</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <div className="space-y-4">
                            {isPositionsLoading && <div className="text-muted-foreground text-sm p-4">Loading positions...</div>}
                            {!isPositionsLoading && (!userPositions || userPositions.length === 0) && (
                                <div className="text-muted-foreground text-sm p-4 border border-dashed border-border/50 rounded-xl bg-secondary/10 text-center py-8">
                                    No active V4 pool positions found for this wallet.
                                </div>
                            )}
                            {userPositions?.map((pos) => {
                                const pool = pools?.find(p => p.poolId === pos.poolId)
                                if (!pool) return null

                                const fee0Bal = balances?.find(b => b.token.toLowerCase() === pool.token0.address.toLowerCase())
                                const fee1Bal = balances?.find(b => b.token.toLowerCase() === pool.token1.address.toLowerCase())
                                const fee0 = fee0Bal ? Number(formatUnits(BigInt(fee0Bal.earnedFees), pool.token0.decimals)) : 0
                                const fee1 = fee1Bal ? Number(formatUnits(BigInt(fee1Bal.earnedFees), pool.token1.decimals)) : 0
                                const isETH0 = pool.token0.symbol.toLowerCase().includes('eth')
                                const isETH1 = pool.token1.symbol.toLowerCase().includes('eth')
                                const feeUsd = (isETH0 ? fee0 * 2000 : fee0) + (isETH1 ? fee1 * 2000 : fee1)

                                return (
                                    <div
                                        key={pos.positionId}
                                        className="group relative overflow-hidden rounded-xl border border-border/50 bg-secondary/20 p-5 transition-all hover:border-border hover:bg-secondary/40"
                                    >
                                        <div className="relative flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                                            <div className="flex-1 space-y-3">
                                                {/* Header row */}
                                                <div className="flex items-center gap-3">
                                                    <h3 className="text-base font-semibold">{pool.token0.symbol}/{pool.token1.symbol} ({pool.fee / 10000}%)</h3>
                                                    {getStatusBadge(pos.active ? "active" : "completed")}
                                                    <div className="flex items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-0.5">
                                                        <TrendingUp className="h-3 w-3 text-emerald-400" />
                                                        <span className="text-xs font-semibold text-emerald-400">JIT Enabled</span>
                                                    </div>
                                                </div>

                                                {/* Stats row */}
                                                <div className="flex flex-wrap items-center gap-x-6 gap-y-3 text-sm">
                                                    <div>
                                                        <span className="text-muted-foreground block mb-1">Tick Range</span>
                                                        <Badge variant="secondary" className="font-mono text-[10px]">{pos.tickLower} ↔ {pos.tickUpper}</Badge>
                                                    </div>
                                                    <div>
                                                        <span className="text-muted-foreground block mb-1">Virtual Shares</span>
                                                        <p className="font-semibold tabular-nums text-xs">{Number(formatUnits(BigInt(pos.liquidityShares), 18)).toExponential(2)}</p>
                                                    </div>
                                                </div>
                                            </div>

                                            {/* Fees Panel — prominent on the right */}
                                            <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4 min-w-[200px]">
                                                <p className="text-xs uppercase tracking-wider text-emerald-400/80 mb-2">Earned Fees</p>
                                                <p className="text-xl font-bold text-emerald-400 tabular-nums">
                                                    ~${feeUsd.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                                                </p>
                                                <div className="mt-2 space-y-1 text-xs font-mono text-muted-foreground">
                                                    <div className="flex justify-between">
                                                        <span>{pool.token0.symbol}</span>
                                                        <span className="text-emerald-400">+{fee0.toFixed(4)}</span>
                                                    </div>
                                                    <div className="flex justify-between">
                                                        <span>{pool.token1.symbol}</span>
                                                        <span className="text-emerald-400">+{fee1.toFixed(4)}</span>
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                )
                            })}
                        </div>
                    </CardContent>
                </Card>

                {/* Transaction History — TODO: wire to real on-chain data */}
            </div>
        </div>
    )
}
