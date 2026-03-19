import { useMemo } from 'react'
import { usePositions, usePositionSummary } from './use-positions'
import { useStrategies } from './use-strategies'
import { useTokens } from './use-tokens'
import { useSwapHistory } from './use-swaps'
import { mapApiPosition, mapApiSwapToTransaction } from '@/lib/api-mappers'
import type { Position, Transaction, UserStats } from '@/lib/types'

/** Fetches positions and maps them to frontend Position type */
export function useMappedPositions(wallet?: string) {
  const { data: positionsData, isLoading: posLoading, error: posError } = usePositions(wallet)
  const { data: apiStrategies, isLoading: stratLoading } = useStrategies()

  const positions: Position[] | undefined = useMemo(() => {
    if (!positionsData || !apiStrategies) return undefined
    return positionsData.positions.map((p) => mapApiPosition(p, apiStrategies))
  }, [positionsData, apiStrategies])

  return {
    data: positions,
    isLoading: posLoading || stratLoading,
    error: posError,
  }
}

/** Builds UserStats from position summary */
export function useMappedUserStats(wallet?: string) {
  const { data: summary, isLoading, error } = usePositionSummary(wallet)

  const stats: UserStats | undefined = useMemo(() => {
    if (!summary) return undefined
    return {
      totalLiquidityDeployed: summary.totalValueUsd,
      totalEarnings: summary.totalEarnedFeesUsd,
      activePositions: summary.activeStrategies,
      averageApy: 0, // Not available from summary endpoint
    }
  }, [summary])

  return { data: stats, isLoading, error }
}

/** Fetches swap history and maps to frontend Transaction type */
export function useMappedTransactions(wallet?: string) {
  const { data: swaps, isLoading: swapsLoading, error: swapsError } = useSwapHistory(wallet)
  const { data: tokens, isLoading: tokensLoading } = useTokens()

  const transactions: Transaction[] | undefined = useMemo(() => {
    if (!swaps || !tokens) return undefined
    return swaps.map((s) => mapApiSwapToTransaction(s, tokens))
  }, [swaps, tokens])

  return {
    data: transactions,
    isLoading: swapsLoading || tokensLoading,
    error: swapsError,
  }
}
