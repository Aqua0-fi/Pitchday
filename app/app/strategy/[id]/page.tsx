"use client"

import { useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { TokenPairIcon } from '@/components/token-icon'
import { LoadingSpinner } from '@/components/loading-spinner'
import { useMappedStrategy } from '@/hooks/use-mapped-strategies'
import type { Strategy } from '@/lib/types'
import {
  ArrowLeft,
  ArrowUpRight,
  TrendingUp,
  ExternalLink,
  CheckCircle2,
} from 'lucide-react'
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'
import { AddLiquidityModal } from '@/components/strategies/add-liquidity-modal'
import Image from 'next/image'

interface StrategyDetail {
  strategy: Strategy
  volume24h: number
  volume7d: number
  fees24h: number
  fees7d: number
  fees30d: number
  totalFeesCollected: number
  poolComposition: { tokenA: number; tokenB: number }
  tokenAAmount: number
  tokenBAmount: number
  currentPrice: number
  minPrice?: number
  maxPrice?: number
  inRange?: boolean
  liquidityActive?: number
  utilizationRate?: number
  impermanentLoss?: number
  distanceFromUpper?: number
  distanceFromLower?: number
  tickDistribution?: { price: number; liquidity: number }[]
  priceHistory?: { date: string; price: number }[]
  apyHistory: { date: string; apy: number }[]
  tvlHistory: { date: string; tvl: number }[]
  volumeHistory: { date: string; volume: number }[]
  recentActivity: { id: string; type: string; amount: string; price: string; time: string; hash: string }[]
  userPosition: { hasPosition: boolean; value: number; earnings: number; share: number }
}

const strategyTypeLabels: Record<string, string> = {
  'constant-product': 'Constant Product',
  'stable-swap': 'Stable Swap',
}

const strategyTypeColors: Record<string, string> = {
  'constant-product': 'bg-violet-500/10 text-violet-400',
  'stable-swap': 'bg-sky-500/10 text-sky-400',
}

function formatCurrency(value: number): string {
  if (value >= 1_000_000) return `$${(value / 1_000_000).toFixed(2)}M`
  if (value >= 1_000) return `$${(value / 1_000).toFixed(1)}K`
  return `$${value.toFixed(2)}`
}

function formatNumber(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)}M`
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}K`
  return value.toFixed(2)
}

export default function StrategyDetailPage() {
  const params = useParams()
  const router = useRouter()
  const strategyHash = params.id as string
  const { data: mappedStrategy, raw: apiDetail, isLoading } = useMappedStrategy(strategyHash)
  const [chartMetric, setChartMetric] = useState<'apy' | 'tvl' | 'volume'>('apy')
  const [isAddLiquidityOpen, setIsAddLiquidityOpen] = useState(false)

  // Build StrategyDetail from API data with defaults for fields not yet available
  const data: StrategyDetail | null = mappedStrategy ? {
    strategy: mappedStrategy,
    volume24h: apiDetail?.volume24hUsd ?? 0,
    volume7d: 0,
    fees24h: 0,
    fees7d: 0,
    fees30d: 0,
    totalFeesCollected: apiDetail?.stats ? parseFloat(apiDetail.stats.totalFees) / 1e18 : 0,
    poolComposition: { tokenA: 50, tokenB: 50 },
    tokenAAmount: 0,
    tokenBAmount: 0,
    currentPrice: 0,
    apyHistory: [],
    tvlHistory: [],
    volumeHistory: [],
    recentActivity: [],
    userPosition: { hasPosition: false, value: 0, earnings: 0, share: 0 },
  } : null

  if (isLoading) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center">
        <LoadingSpinner size="lg" />
      </div>
    )
  }

  if (!data) {
    return (
      <div className="flex min-h-[60vh] flex-col items-center justify-center gap-4">
        <p className="text-muted-foreground">Strategy not found</p>
        <Button variant="outline" onClick={() => router.push('/')}>
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to Strategies
        </Button>
      </div>
    )
  }

  const { strategy } = data
  const isStableSwap = strategy.type === 'stable-swap'
  const isConstantProduct = strategy.type === 'constant-product'

  // Prepare chart data based on selected metric
  const getChartData = () => {
    switch (chartMetric) {
      case 'apy':
        return data.apyHistory.map(d => ({ date: d.date, value: d.apy }))
      case 'tvl':
        return data.tvlHistory.map(d => ({ date: d.date, value: d.tvl }))
      case 'volume':
        return data.volumeHistory.map(d => ({ date: d.date, value: d.volume }))
    }
  }

  const chartData = getChartData()

  return (
    <div className="container mx-auto px-4 py-8">
      {/* Back button */}
      <Link 
        href="/" 
        className="mb-6 inline-flex items-center text-sm text-muted-foreground transition-colors hover:text-foreground"
      >
        <ArrowLeft className="mr-2 h-4 w-4" />
        Back to Strategies
      </Link>

      {/* Header Section */}
      <div className="mb-8 flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
        <div className="flex items-center gap-4">
          <TokenPairIcon tokens={strategy.tokenPair} size="lg" />
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-2xl font-bold">{strategy.name}</h1>
              <span className={`px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full ${strategyTypeColors[strategy.type] || 'bg-white/5 text-muted-foreground'}`}>
                {strategyTypeLabels[strategy.type]}
              </span>
              <span className="px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full bg-white/5 text-muted-foreground">
                {strategy.supportedChains[0]?.name}
              </span>
            </div>
            <p className="mt-1 text-sm text-muted-foreground">
              {strategy.tokenPair[0].symbol}/{strategy.tokenPair[1].symbol} - Fee: {strategy.feeTier}%
            </p>
          </div>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1.5 rounded-full bg-emerald-500/10 px-3 py-1.5">
            <TrendingUp className="h-3.5 w-3.5 text-emerald-400" />
            <span className="text-sm font-bold text-emerald-400">{strategy.apy.toFixed(1)}% APY</span>
          </div>
          <Button size="lg" className="gap-2" onClick={() => setIsAddLiquidityOpen(true)}>
            Deploy Liquidity
            <ArrowUpRight className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Key Metrics Row */}
      <div className="mb-8 grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-5">
        {[
          { label: 'Total vTVL', value: formatCurrency(strategy.tvl) },
          { label: '24h Volume', value: formatCurrency(data.volume24h) },
          { label: '24h Fees', value: formatCurrency(data.fees24h) },
          { label: 'Fee Tier', value: `${strategy.feeTier}%` },
          ...(data.userPosition.hasPosition
            ? [{ label: 'Your Position', value: formatCurrency(data.userPosition.value), color: 'text-emerald-400' }]
            : []),
        ].map((metric) => (
          <div
            key={metric.label}
            className="rounded-xl border border-border/50 bg-secondary/20 p-4"
          >
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{metric.label}</p>
            <p className={`mt-1.5 text-xl font-bold tabular-nums ${metric.color || ''}`}>{metric.value}</p>
          </div>
        ))}
      </div>

      {/* Main Content - Different layouts per strategy type */}
      {isStableSwap && (
        <StableSwapView data={data} chartData={chartData} chartMetric={chartMetric} setChartMetric={setChartMetric} />
      )}
      
      {isConstantProduct && (
        <ConstantProductView data={data} chartData={chartData} chartMetric={chartMetric} setChartMetric={setChartMetric} />
      )}

      {/* Add Liquidity Modal */}
      <AddLiquidityModal
        open={isAddLiquidityOpen}
        onOpenChange={setIsAddLiquidityOpen}
        strategy={strategy}
        currentPrice={data.currentPrice}
        minPrice={data.minPrice}
        maxPrice={data.maxPrice}
      />
    </div>
  )
}

// Shared Sidebar Stats
function SidebarStats({ data, showSlippage }: { data: StrategyDetail; showSlippage?: boolean }) {
  const volumeRows = [
    { label: showSlippage ? '24h Swaps' : '24h Volume', value: formatCurrency(data.volume24h) },
    { label: '7d Volume', value: formatCurrency(data.volume7d) },
    ...(showSlippage
      ? [{ label: 'Avg Slippage', value: '0.01%', color: 'text-emerald-400' }]
      : [{ label: 'Vol/TVL Ratio', value: `${((data.volume24h / data.strategy.tvl) * 100).toFixed(2)}%` }]),
  ]
  const feeRows = [
    { label: '24h Fees', value: formatCurrency(data.fees24h) },
    { label: '7d Fees', value: formatCurrency(data.fees7d) },
    { label: '30d Fees', value: formatCurrency(data.fees30d) },
  ]

  return (
    <>
      <div className="rounded-xl border border-border/50 bg-secondary/20 p-5">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground mb-4">{showSlippage ? 'Swap Statistics' : 'Volume Statistics'}</p>
        <div className="space-y-3">
          {volumeRows.map((r) => (
            <div key={r.label} className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">{r.label}</span>
              <span className={`font-semibold tabular-nums ${r.color || ''}`}>{r.value}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="rounded-xl border border-border/50 bg-secondary/20 p-5">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground mb-4">Fee Statistics</p>
        <div className="space-y-3">
          {feeRows.map((r) => (
            <div key={r.label} className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">{r.label}</span>
              <span className="font-semibold tabular-nums">{r.value}</span>
            </div>
          ))}
          <div className="border-t border-border/50 pt-3">
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">Total Collected</span>
              <span className="font-bold tabular-nums text-emerald-400">{formatCurrency(data.totalFeesCollected)}</span>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}

// Shared Pool Balance Component
function PoolBalance({ data, strategy, showUsdValues }: { data: StrategyDetail; strategy: Strategy; showUsdValues?: (symbol: string, amount: number) => string }) {
  return (
    <div className="rounded-xl border border-border/50 bg-secondary/20 p-5">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground mb-4">Pool Reserves</p>
      <div className="grid grid-cols-2 gap-3">
        <div className="rounded-lg bg-white/[0.03] p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-semibold">{strategy.tokenPair[0].symbol}</span>
            <span className="text-xs text-muted-foreground">{data.poolComposition.tokenA}%</span>
          </div>
          <p className="text-xl font-bold tabular-nums">{formatNumber(data.tokenAAmount)}</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {showUsdValues ? showUsdValues(strategy.tokenPair[0].symbol, data.tokenAAmount) : formatCurrency(data.tokenAAmount)}
          </p>
        </div>
        <div className="rounded-lg bg-white/[0.03] p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-semibold">{strategy.tokenPair[1].symbol}</span>
            <span className="text-xs text-muted-foreground">{data.poolComposition.tokenB}%</span>
          </div>
          <p className="text-xl font-bold tabular-nums">{formatNumber(data.tokenBAmount)}</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {showUsdValues ? showUsdValues(strategy.tokenPair[1].symbol, data.tokenBAmount) : formatCurrency(data.tokenBAmount)}
          </p>
        </div>
      </div>
      {/* Balance Bar */}
      <div className="mt-4 flex h-2 w-full overflow-hidden rounded-full bg-white/[0.03]">
        <div
          className="h-full rounded-full transition-all duration-500"
          style={{
            width: `${data.poolComposition.tokenA}%`,
            background: 'linear-gradient(90deg, #10b981, #10b981cc)',
            boxShadow: '0 0 8px #10b98144',
          }}
        />
      </div>
      <p className="mt-2 text-center text-xs text-muted-foreground">
        Pool is {Math.abs(data.poolComposition.tokenA - 50) < 2 ? 'well balanced' : 'slightly imbalanced'}
      </p>
    </div>
  )
}

// Stable Swap View
function StableSwapView({
  data,
  chartData,
  chartMetric,
  setChartMetric
}: {
  data: StrategyDetail
  chartData: { date: string; value: number }[]
  chartMetric: 'apy' | 'tvl' | 'volume'
  setChartMetric: (m: 'apy' | 'tvl' | 'volume') => void
}) {
  const { strategy } = data

  return (
    <div className="grid gap-4 lg:grid-cols-3">
      {/* Left Column */}
      <div className="space-y-4 lg:col-span-2">
        {/* Peg Status */}
        <div className="rounded-xl border border-border/50 bg-secondary/20 p-5">
          <div className="flex items-center justify-between mb-4">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Peg Status</p>
            <div className="flex items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-0.5">
              <CheckCircle2 className="h-3 w-3 text-emerald-400" />
              <span className="text-xs font-semibold text-emerald-400">Stable</span>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="rounded-lg bg-white/[0.03] p-4 text-center">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Current Rate</p>
              <p className="mt-2 text-3xl font-bold tabular-nums">{data.currentPrice.toFixed(4)}</p>
              <p className="mt-1 text-xs text-muted-foreground">
                1 {strategy.tokenPair[0].symbol} = {data.currentPrice.toFixed(4)} {strategy.tokenPair[1].symbol}
              </p>
            </div>
            <div className="rounded-lg bg-white/[0.03] p-4 text-center">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Deviation from Peg</p>
              <p className="mt-2 text-3xl font-bold tabular-nums text-emerald-400">
                {((data.currentPrice - 1) * 100).toFixed(3)}%
              </p>
              <p className="mt-1 text-xs text-muted-foreground">Target: 1.0000</p>
            </div>
          </div>
        </div>

        <PoolBalance data={data} strategy={strategy} />

        <PerformanceChart
          chartData={chartData}
          chartMetric={chartMetric}
          setChartMetric={setChartMetric}
        />
      </div>

      {/* Right Column */}
      <div className="space-y-4">
        <SidebarStats data={data} showSlippage />
        <RecentActivityCard activities={data.recentActivity} />
      </div>
    </div>
  )
}

// Constant Product View
function ConstantProductView({
  data,
  chartData,
  chartMetric,
  setChartMetric
}: {
  data: StrategyDetail
  chartData: { date: string; value: number }[]
  chartMetric: 'apy' | 'tvl' | 'volume'
  setChartMetric: (m: 'apy' | 'tvl' | 'volume') => void
}) {
  const { strategy } = data
  const getUsdValue = (symbol: string, amount: number) => {
    const prices: Record<string, number> = { WBTC: 42000, ETH: 2000, USDC: 1, USDT: 1, DAI: 1 }
    return formatCurrency(amount * (prices[symbol] || 1))
  }

  return (
    <div className="grid gap-4 lg:grid-cols-3">
      {/* Left Column */}
      <div className="space-y-4 lg:col-span-2">
        {/* AMM State */}
        <div className="rounded-xl border border-border/50 bg-secondary/20 p-5">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground mb-4">AMM State</p>
          <div className="grid grid-cols-3 gap-3">
            <div className="rounded-lg bg-white/[0.03] p-4 text-center">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Current Price</p>
              <p className="mt-2 text-2xl font-bold tabular-nums">{formatCurrency(data.currentPrice)}</p>
              <p className="mt-1 text-xs text-muted-foreground">
                1 {strategy.tokenPair[0].symbol} = {data.currentPrice.toFixed(2)} {strategy.tokenPair[1].symbol}
              </p>
            </div>
            <div className="rounded-lg bg-white/[0.03] p-4 text-center">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Constant K</p>
              <p className="mt-2 text-2xl font-bold tabular-nums">{formatNumber(data.tokenAAmount * data.tokenBAmount)}</p>
              <p className="mt-1 text-xs text-muted-foreground">x * y = k</p>
            </div>
            <div className="rounded-lg bg-white/[0.03] p-4 text-center">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Price Impact (1%)</p>
              <p className="mt-2 text-2xl font-bold tabular-nums">0.5%</p>
              <p className="mt-1 text-xs text-muted-foreground">Est. slippage</p>
            </div>
          </div>
        </div>

        <PoolBalance data={data} strategy={strategy} showUsdValues={getUsdValue} />

        <PerformanceChart
          chartData={chartData}
          chartMetric={chartMetric}
          setChartMetric={setChartMetric}
        />
      </div>

      {/* Right Column */}
      <div className="space-y-4">
        <SidebarStats data={data} />
        <RecentActivityCard activities={data.recentActivity} />
      </div>
    </div>
  )
}

// Shared Performance Chart Component
function PerformanceChart({
  chartData,
  chartMetric,
  setChartMetric
}: {
  chartData: { date: string; value: number }[]
  chartMetric: 'apy' | 'tvl' | 'volume'
  setChartMetric: (m: 'apy' | 'tvl' | 'volume') => void
}) {
  return (
    <div className="rounded-xl border border-border/50 bg-secondary/20 overflow-hidden">
      <div className="flex items-center justify-between p-5 pb-2">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Performance</p>
        <Tabs value={chartMetric} onValueChange={(v) => setChartMetric(v as typeof chartMetric)}>
          <TabsList className="h-7 bg-white/[0.03]">
            <TabsTrigger value="apy" className="text-[10px] uppercase tracking-wider h-5 px-2.5">APY</TabsTrigger>
            <TabsTrigger value="tvl" className="text-[10px] uppercase tracking-wider h-5 px-2.5">TVL</TabsTrigger>
            <TabsTrigger value="volume" className="text-[10px] uppercase tracking-wider h-5 px-2.5">Volume</TabsTrigger>
          </TabsList>
        </Tabs>
      </div>
      <div className="px-2 pb-4">
        <div className="h-[240px]">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={chartData} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="perfGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#10b981" stopOpacity={0.35} />
                  <stop offset="50%" stopColor="#10b981" stopOpacity={0.12} />
                  <stop offset="100%" stopColor="#10b981" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="perfLine" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%" stopColor="#10b981" />
                  <stop offset="100%" stopColor="#34d399" />
                </linearGradient>
                <filter id="perfGlow">
                  <feGaussianBlur stdDeviation="3" result="coloredBlur" />
                  <feMerge>
                    <feMergeNode in="coloredBlur" />
                    <feMergeNode in="SourceGraphic" />
                  </feMerge>
                </filter>
              </defs>
              <XAxis
                dataKey="date"
                stroke="#6b7280"
                fontSize={11}
                tickLine={false}
                axisLine={false}
                dy={8}
              />
              <YAxis
                stroke="#6b7280"
                fontSize={11}
                tickLine={false}
                axisLine={false}
                tickFormatter={(v) => chartMetric === 'apy' ? `${v}%` : formatNumber(v)}
                width={52}
              />
              <Tooltip
                content={({ active, payload, label }) => {
                  if (!active || !payload?.length) return null
                  const v = payload[0].value as number
                  return (
                    <div className="rounded-xl border border-white/10 bg-black/80 px-4 py-3 shadow-2xl backdrop-blur-md">
                      <p className="text-xs text-muted-foreground mb-1">{label}</p>
                      <p className="text-lg font-bold text-emerald-400">
                        {chartMetric === 'apy' ? `${v.toFixed(1)}%` : formatCurrency(v)}
                      </p>
                      <p className="text-xs text-emerald-500/60">{chartMetric.toUpperCase()}</p>
                    </div>
                  )
                }}
                cursor={{ stroke: '#10b98133', strokeWidth: 1, strokeDasharray: '4 4' }}
              />
              <Area
                type="monotone"
                dataKey="value"
                stroke="url(#perfLine)"
                strokeWidth={2.5}
                fill="url(#perfGradient)"
                filter="url(#perfGlow)"
                dot={false}
                activeDot={{ r: 6, fill: '#10b981', stroke: '#10b98140', strokeWidth: 8 }}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  )
}

// Shared Recent Activity Component
function RecentActivityCard({ activities }: { activities: { id: string; type: string; amount: string; price: string; time: string; hash: string }[] }) {
  const getActivityIcon = (type: string) => {
    const iconMap: Record<string, string> = {
      swap: '/icons/Swap.png',
      add: '/icons/Deposit.png',
      remove: '/icons/Withdraw.png',
    }
    const iconPath = iconMap[type] || '/icons/Swap.png'
    return (
      <Image
        src={iconPath}
        alt={type}
        width={20}
        height={20}
        className="h-5 w-5"
        unoptimized
      />
    )
  }

  return (
    <div className="rounded-xl border border-border/50 bg-secondary/20 p-5">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground mb-4">Recent Activity</p>
      <div className="space-y-3">
        {activities.slice(0, 5).map((activity) => (
          <div key={activity.id} className="flex items-center justify-between text-sm">
            <div className="flex items-center gap-2">
              {getActivityIcon(activity.type)}
              <div>
                <p className="font-medium capitalize">{activity.type}</p>
                <p className="text-xs text-muted-foreground">{activity.time}</p>
              </div>
            </div>
            <div className="text-right">
              <p className="font-medium tabular-nums">{activity.amount}</p>
              <a
                href={`https://etherscan.io/tx/${activity.hash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center text-xs text-muted-foreground hover:text-emerald-400 transition-colors"
              >
                {activity.hash.slice(0, 8)}...
                <ExternalLink className="ml-1 h-3 w-3" />
              </a>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
