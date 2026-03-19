"use client"

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { TokenPairIcon } from '@/components/token-icon'
import type { Strategy } from '@/lib/types'
import { ArrowUpRight, TrendingUp } from 'lucide-react'
import Image from 'next/image'

interface StrategyCardProps {
  strategy: Strategy
}

const strategyTypeLabels: Record<string, string> = {
  'constant-product': 'Constant Product',
  'stable-swap': 'Stable Swap',
}

const strategyTypeColors: Record<string, string> = {
  'constant-product': 'bg-violet-500/10 text-violet-400',
  'stable-swap': 'bg-sky-500/10 text-sky-400',
}

function formatTVL(tvl: number): string {
  if (tvl >= 1_000_000) {
    return `$${(tvl / 1_000_000).toFixed(1)}M`
  }
  if (tvl >= 1_000) {
    return `$${(tvl / 1_000).toFixed(0)}K`
  }
  return `$${tvl.toFixed(0)}`
}

export function StrategyCard({ strategy }: StrategyCardProps) {
  const router = useRouter()

  const handleSeeDetails = (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    router.push(`/strategy/${strategy.id}`)
  }

  const chain = strategy.supportedChains[0]

  return (
    <Card className="group relative flex h-full flex-col overflow-hidden border-border/50 bg-secondary/20 transition-all duration-300 hover:border-border hover:bg-secondary/40">
      <Link href={`/strategy/${strategy.id}`} className="absolute inset-0 z-10">
        <span className="sr-only">View {strategy.name} details</span>
      </Link>

      {/* Hover glow */}
      <div className="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-300 group-hover:opacity-100" style={{ background: 'radial-gradient(ellipse at top left, #10b98106, transparent 70%)' }} />

      <CardContent className="relative flex-1 p-5">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <TokenPairIcon tokens={strategy.tokenPair} size="lg" />
            <div>
              {strategy.name !== `${strategy.tokenPair[0].symbol}/${strategy.tokenPair[1].symbol}` && (
                <p className="text-xs font-medium text-muted-foreground">{strategy.name}</p>
              )}
              <h3 className="text-base font-semibold">
                {strategy.tokenPair[0].symbol}/{strategy.tokenPair[1].symbol}
              </h3>
              <span className={`inline-block mt-0.5 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded-full ${strategyTypeColors[strategy.type] || 'bg-white/5 text-muted-foreground'}`}>
                {strategyTypeLabels[strategy.type]}
              </span>
            </div>
          </div>
          {/* APY badge */}
          <div className="flex items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-1">
            <TrendingUp className="h-3 w-3 text-emerald-400" />
            <span className="text-sm font-bold text-emerald-400">{strategy.apy.toFixed(1)}%</span>
          </div>
        </div>

        {/* Metrics */}
        <div className="mt-5 grid grid-cols-3 gap-3">
          <div className="rounded-lg bg-white/[0.03] p-3">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground">vTVL</p>
            <p className="mt-1 text-lg font-bold tabular-nums">{formatTVL(strategy.tvl)}</p>
          </div>
          <div className="rounded-lg bg-white/[0.03] p-3">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Fee</p>
            <p className="mt-1 text-lg font-bold tabular-nums">{strategy.feeTier}%</p>
          </div>
          <div className="rounded-lg bg-white/[0.03] p-3">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground">Chain</p>
            <div className="mt-1 flex items-center gap-1.5">
              {chain && (
                <Image
                  src={chain.logo}
                  alt={chain.name}
                  width={18}
                  height={18}
                  className="rounded-full"
                  unoptimized
                />
              )}
              <span className="text-sm font-semibold">{chain?.name || 'N/A'}</span>
            </div>
          </div>
        </div>

        {/* CTA */}
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

export function StrategyCardSkeleton() {
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

        <div className="mt-5 grid grid-cols-3 gap-3">
          {[1, 2, 3].map((i) => (
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
