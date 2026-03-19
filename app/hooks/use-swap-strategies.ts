import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { StrategiesResponse, StrategyDetailResponse, ApiStrategy } from '@/lib/api-types'

/**
 * Discover strategies available for a token pair.
 * Searches both directions (A→B and B→A) since the router handles directionality.
 * Also fetches bytecode for the best strategy (needed for order.data).
 */
export function useSwapStrategies(
  tokenIn?: string,
  tokenOut?: string,
  chainId?: number,
) {
  // Find active strategies for this pair (both directions)
  const {
    data: strategies,
    isLoading: isLoadingStrategies,
    error: strategiesError,
  } = useQuery({
    queryKey: ['swap-strategies', tokenIn, tokenOut, chainId],
    queryFn: async () => {
      const params = { chainId: String(chainId!) }

      const [forward, reverse] = await Promise.all([
        api.get<StrategiesResponse>('strategies', {
          ...params,
          tokenIn: tokenIn!,
          tokenOut: tokenOut!,
        }),
        api.get<StrategiesResponse>('strategies', {
          ...params,
          tokenIn: tokenOut!,
          tokenOut: tokenIn!,
        }),
      ])

      // Combine, deduplicate by hash, keep only active
      const seen = new Set<string>()
      const combined: ApiStrategy[] = []
      for (const s of [...forward.strategies, ...reverse.strategies]) {
        if (s.isActive && !seen.has(s.strategyHash)) {
          seen.add(s.strategyHash)
          combined.push(s)
        }
      }

      // Sort by TVL descending (best liquidity first)
      combined.sort((a, b) => (b.tvlUsd ?? 0) - (a.tvlUsd ?? 0))
      return combined
    },
    enabled: !!tokenIn && !!tokenOut && !!chainId,
    staleTime: 30 * 1000, // 30s — strategies don't change often
  })

  // Fetch detail (with bytecode) for the best strategy
  const bestHash = strategies?.[0]?.strategyHash
  const {
    data: bestStrategy,
    isLoading: isLoadingDetail,
  } = useQuery({
    queryKey: ['strategy', bestHash],
    queryFn: () => api.get<StrategyDetailResponse>(`strategies/${bestHash}`),
    select: (data) => data.strategy,
    enabled: !!bestHash,
    staleTime: 5 * 60 * 1000,
  })

  return {
    strategies: strategies ?? [],
    bestStrategy: bestStrategy ?? null,
    hasLiquidity: (strategies?.length ?? 0) > 0,
    isLoading: isLoadingStrategies || (!!bestHash && isLoadingDetail),
    error: strategiesError,
  }
}
