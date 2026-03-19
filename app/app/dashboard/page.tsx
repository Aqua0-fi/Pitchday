"use client"

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
} from '@/components/ui/table'
import { TokenPairIcon } from '@/components/token-icon'
import { useWallet } from '@/contexts/wallet-context'
import {
    Wallet,
    Plus,
    Minus,
    ExternalLink,
    TrendingUp,
} from 'lucide-react'
import Image from 'next/image'
import { RealLiquidityManager } from '@/components/dashboard/real-liquidity-manager'
import { useV4Pools } from '@/hooks/use-v4-pools'
import { useUserPositions } from '@/hooks/use-user-positions'
import { VisualLiquidityChart } from '@/components/pools/visual-liquidity-chart'
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

    // Very naive USD conversion placeholder for fees (treating all tokens as 1:1 USD for MVP demo purposes or just summing them up)
    // In a real app we would multiply by token price.
    const totalEarnedFeesUsd = balances?.reduce((acc, bal) => {
        const token = pools?.flatMap(p => [p.token0, p.token1]).find(t => t.address.toLowerCase() === bal.token.toLowerCase())
        if (!token || !bal.earnedFees) return acc
        // MVP Placeholder: Assume 1 token = $1 or just sum raw units to show *something* changing
        // A better approach would be to use currentPrice, but we'll just sum formatted amounts for demo
        return acc + Number(formatUnits(BigInt(bal.earnedFees), token.decimals))
    }, 0) || 0

    const formatCurrency = (value: number) => {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0,
        }).format(value)
    }

    const formatDate = (dateString: string) => {
        return new Date(dateString).toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
        })
    }

    const getTransactionIcon = (type: string) => {
        const iconMap: Record<string, string> = {
            deposit: '/icons/Deposit.png',
            withdraw: '/icons/Withdraw.png',
            'withdraw fees': '/icons/Gift.png',
        }
        return (
            <Image
                src={iconMap[type] || '/icons/Swap.png'}
                alt={type}
                width={20}
                height={20}
                className="h-5 w-5"
                unoptimized
            />
        )
    }

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
                        { label: 'Uncollected Fees (Raw Sum MVP)', value: `+${totalEarnedFeesUsd.toFixed(4)}`, color: 'text-emerald-400' }, // Placeholder MVP summation
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

                {/* Active Positions */}
                <Card className="mb-8">
                    <CardHeader>
                        <CardTitle>Your V4 Pool Positions</CardTitle>
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

                                return (
                                    <div
                                        key={pos.positionId}
                                        className="group relative overflow-hidden rounded-xl border border-border/50 bg-secondary/20 p-5 transition-all hover:border-border hover:bg-secondary/40"
                                    >
                                        <div className="relative flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
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
                                                    <div>
                                                        <span className="text-muted-foreground block mb-1">Earned Fees</span>
                                                        <p className="font-semibold tabular-nums text-emerald-400">
                                                            +{(
                                                                (balances?.find(b => b.token.toLowerCase() === pool.token0.address.toLowerCase()) ?
                                                                    Number(formatUnits(BigInt(balances.find(b => b.token.toLowerCase() === pool.token0.address.toLowerCase())!.earnedFees), pool.token0.decimals)).toFixed(4) : "0.0000")
                                                                + " " + pool.token0.symbol
                                                            )} / +{(
                                                                (balances?.find(b => b.token.toLowerCase() === pool.token1.address.toLowerCase()) ?
                                                                    Number(formatUnits(BigInt(balances.find(b => b.token.toLowerCase() === pool.token1.address.toLowerCase())!.earnedFees), pool.token1.decimals)).toFixed(4) : "0.0000")
                                                                + " " + pool.token1.symbol
                                                            )}
                                                        </p>
                                                    </div>
                                                    <div>
                                                        <span className="text-[10px] font-mono text-muted-foreground/60 block mt-1">ID: {pos.positionId.slice(0, 10)}...</span>
                                                    </div>
                                                </div>
                                            </div>

                                            {/* Actions */}
                                            <div className="flex flex-col gap-2">
                                                <Button variant="outline" size="sm" className="border-border/50 bg-secondary/50 hover:bg-secondary">
                                                    <Plus className="mr-1 h-4 w-4" />
                                                    Add More
                                                </Button>
                                                <Button variant="outline" size="sm" className="border-border/50 bg-secondary/50 hover:bg-secondary text-red-400 hover:text-red-300">
                                                    <Minus className="mr-1 h-4 w-4" />
                                                    Remove
                                                </Button>
                                            </div>
                                        </div>

                                        {/* Embedded Virtual Chart */}
                                        <div className="mt-6 pt-4 border-t border-border/50">
                                            <h4 className="text-sm font-semibold mb-3 text-muted-foreground">Virtual Distribution</h4>
                                            <VisualLiquidityChart pool={pool} />
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
