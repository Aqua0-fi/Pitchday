"use client"

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { PoolCard, PoolCardSkeleton } from '@/components/pools/pool-card'
import { useV4Pools } from '@/hooks/use-v4-pools'
import { Info, Search } from 'lucide-react'
import { useWallet } from '@/contexts/wallet-context'

export default function PoolsMarketplacePage() {
  const { isConnected, connect, chainId } = useWallet()
  const activeChainId = chainId || Number(process.env.NEXT_PUBLIC_CHAIN_ID || 84532)
  const { data: pools, isLoading } = useV4Pools(activeChainId)

  return (
    <div className="min-h-screen">
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-3xl font-bold">Aqua0 Shared Liquidity Pools</h1>
            <p className="mt-1 text-muted-foreground flex items-center gap-1.5">
              Provide cross-chain shared liquidity into Uniswap V4.
            </p>
          </div>
          {!isConnected && (
            <Button onClick={connect} className="gap-2">
              Log in to Provide Liquidity
            </Button>
          )}
        </div>

        {/* Info Banner */}
        <div className="mb-6 rounded-lg border border-emerald-500/20 bg-emerald-500/5 p-4 flex items-start gap-3">
          <Info className="h-5 w-5 text-emerald-400 mt-0.5" />
          <div>
            <h4 className="text-sm font-semibold text-emerald-400">JIT Liquidity Engine Active</h4>
            <p className="text-sm text-emerald-400/80 mt-1">
              Aqua0 acts as a bridge for Uniswap V4 hooks. Liquidity is deposited into the <code>SharedLiquidityPool</code> contract and provided via JIT just-in-time flash accounting right before swaps.
            </p>
          </div>
        </div>

        {/* Strategy Grid */}
        {isLoading ? (
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {[1, 2, 3].map((i) => (
              <PoolCardSkeleton key={i} />
            ))}
          </div>
        ) : !pools || pools.length === 0 ? (
          <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-border py-16">
            <p className="text-lg font-medium">No V4 Pools found on this chain.</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Try switching your network to Base Sepolia, Unichain Sepolia, or Local Anvil (Localhost).
            </p>
          </div>
        ) : (
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {pools.map((pool) => (
              <PoolCard
                key={pool.poolId}
                pool={pool}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

