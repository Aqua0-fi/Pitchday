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
import { ChainIcon } from '@/components/chain-icon'
import { LoadingSpinner } from '@/components/loading-spinner'
import { useWallet } from '@/contexts/wallet-context'
import { useMappedPositions, useMappedUserStats, useMappedTransactions } from '@/hooks/use-mapped-positions'
import { useUser } from '@/hooks/use-users'
import type { Transaction } from '@/lib/types'
import {
  Wallet,
  Plus,
  Minus,
  Eye,
  ExternalLink,
  TrendingUp,
} from 'lucide-react'
import Image from 'next/image'

export default function ProfilePage() {
  const { isConnected, address, email, connect } = useWallet()

  const { data: positions, isLoading: positionsLoading } = useMappedPositions(address || undefined)
  const { data: stats, isLoading: statsLoading } = useMappedUserStats(address || undefined)
  const { data: transactions, isLoading: txLoading } = useMappedTransactions(address || undefined)
  const { data: user } = useUser(address ?? undefined)

  const isLoading = positionsLoading || statsLoading || txLoading

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

  const getTransactionIcon = (type: Transaction['type']) => {
    const iconMap: Record<string, string> = {
      deposit: '/icons/Deposit.png',
      withdraw: '/icons/Withdraw.png',
      swap: '/icons/Swap.png',
      claim: '/icons/Gift.png',
    }
    return (
      <Image
        src={iconMap[type]}
        alt={type}
        width={20}
        height={20}
        className="h-5 w-5"
        unoptimized
      />
    )
  }

  const getStatusBadge = (status: Transaction['status']) => {
    switch (status) {
      case 'completed':
        return <Badge variant="outline" className="bg-green-500/10 text-green-500 border-green-500/20">Completed</Badge>
      case 'pending':
        return <Badge variant="outline" className="bg-yellow-500/10 text-yellow-500 border-yellow-500/20">Pending</Badge>
      case 'failed':
        return <Badge variant="outline" className="bg-red-500/10 text-red-500 border-red-500/20">Failed</Badge>
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
              Connect your wallet to view your positions, earnings, and transaction history.
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

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <LoadingSpinner />
      </div>
    )
  }

  return (
    <div className="min-h-screen">
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-2xl font-bold">Profile</h1>
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mt-1">
            <div className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-emerald-500" />
              <span className="text-sm text-muted-foreground">
                {address ? `${address.slice(0, 6)}\u2026${address.slice(-4)}` : 'Connected'}
              </span>
            </div>
            {email && (
              <span className="text-sm text-muted-foreground">{email}</span>
            )}
            {user?.createdAt && (
              <span className="text-sm text-muted-foreground">
                Member since {new Date(user.createdAt).toLocaleDateString('en-US', { month: 'short', year: 'numeric' })}
              </span>
            )}
          </div>
        </div>

        {/* Stats Cards */}
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 mb-8">
          {[
            { label: 'Total Liquidity', value: formatCurrency(stats?.totalLiquidityDeployed || 0) },
            { label: 'Total Earnings', value: `+${formatCurrency(stats?.totalEarnings || 0)}`, color: 'text-emerald-400' },
            { label: 'Active Positions', value: String(stats?.activePositions || 0) },
            { label: 'Average APY', value: `${(stats?.averageApy ?? 0).toFixed(1)}%`, color: 'text-emerald-400' },
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

        {/* Active Positions */}
        <Card className="mb-8">
          <CardHeader>
            <CardTitle>Active Positions</CardTitle>
          </CardHeader>
          <CardContent>
            {(!positions || positions.length === 0) ? (
              <div className="py-8 text-center">
                <p className="text-muted-foreground">No active positions</p>
              </div>
            ) : (
              <div className="space-y-3">
                {positions.map((position) => {
                  const pnl = position.currentValue - position.deployedAmount
                  const pnlPct = position.deployedAmount > 0
                    ? ((pnl / position.deployedAmount) * 100).toFixed(2)
                    : '0.00'
                  return (
                    <div
                      key={position.id}
                      className="group relative overflow-hidden rounded-xl border border-border/50 bg-secondary/20 p-5 transition-all hover:border-border hover:bg-secondary/40"
                    >
                      {/* Subtle glow accent based on PnL */}
                      <div
                        className="pointer-events-none absolute inset-0 opacity-0 transition-opacity group-hover:opacity-100"
                        style={{
                          background: `radial-gradient(ellipse at top left, ${pnl >= 0 ? '#10b98108' : '#ef444408'}, transparent 70%)`,
                        }}
                      />

                      <div className="relative flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                        <div className="flex-1 space-y-3">
                          {/* Header row */}
                          <div className="flex items-center gap-3">
                            <h3 className="text-base font-semibold">{position.strategyName}</h3>
                            <div className="flex -space-x-1">
                              {position.chains.map((chain) => (
                                <ChainIcon key={chain.id} chain={chain} size="sm" />
                              ))}
                            </div>
                            {position.apy > 0 && (
                              <div className="flex items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-0.5">
                                <TrendingUp className="h-3 w-3 text-emerald-400" />
                                <span className="text-xs font-semibold text-emerald-400">{position.apy}% APY</span>
                              </div>
                            )}
                          </div>

                          {/* Stats row */}
                          <div className="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
                            <div>
                              <span className="text-muted-foreground">Deployed</span>
                              <p className="font-semibold tabular-nums">{formatCurrency(position.deployedAmount)}</p>
                            </div>
                            <div>
                              <span className="text-muted-foreground">Current</span>
                              <p className="font-semibold tabular-nums">{formatCurrency(position.currentValue)}</p>
                            </div>
                            <div>
                              <span className="text-muted-foreground">Earnings</span>
                              <p className="font-semibold tabular-nums text-emerald-400">+{formatCurrency(position.earnings)}</p>
                            </div>
                            <div>
                              <span className="text-muted-foreground">PnL</span>
                              <p className={`font-semibold tabular-nums ${pnl >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                                {pnl >= 0 ? '+' : ''}{pnlPct}%
                              </p>
                            </div>
                          </div>
                        </div>

                        {/* Actions */}
                        <div className="flex gap-2">
                          <Button variant="outline" size="sm" className="border-border/50 bg-secondary/50 hover:bg-secondary">
                            <Plus className="mr-1 h-4 w-4" />
                            Add
                          </Button>
                          <Button variant="outline" size="sm" className="border-border/50 bg-secondary/50 hover:bg-secondary">
                            <Minus className="mr-1 h-4 w-4" />
                            Withdraw
                          </Button>
                          <Button variant="ghost" size="sm">
                            <Eye className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Transaction History */}
        <Card>
          <CardHeader>
            <CardTitle>Recent Transactions</CardTitle>
          </CardHeader>
          <CardContent>
            {(!transactions || transactions.length === 0) ? (
              <div className="py-8 text-center">
                <p className="text-muted-foreground">No transactions yet</p>
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Type</TableHead>
                    <TableHead>Amount</TableHead>
                    <TableHead>Chain</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead className="text-right">Hash</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {transactions.map((tx) => (
                    <TableRow key={tx.id}>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          {getTransactionIcon(tx.type)}
                          <span className="capitalize">{tx.type}</span>
                        </div>
                      </TableCell>
                      <TableCell>
                        {tx.amount.toLocaleString()} {tx.token.symbol}
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <ChainIcon chain={tx.chain} size="sm" />
                          <span className="hidden sm:inline">{tx.chain.name}</span>
                        </div>
                      </TableCell>
                      <TableCell>{getStatusBadge(tx.status)}</TableCell>
                      <TableCell>{formatDate(tx.timestamp)}</TableCell>
                      <TableCell className="text-right">
                        <Button variant="ghost" size="sm" className="h-8 gap-1 px-2">
                          <span className="font-mono text-xs">{tx.hash.slice(0, 10)}...</span>
                          <ExternalLink className="h-3 w-3" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
