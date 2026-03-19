import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { StrategiesResponse, StrategyDetailResponse, StrategyStatsResponse } from '@/lib/api-types'

export interface StrategyFilters {
  chain?: string
  type?: string
  featured?: boolean
  tokenIn?: string
  tokenOut?: string
}

export function useStrategies(filters?: StrategyFilters) {
  const params: Record<string, string> = {}
  if (filters?.chain) params.chain = filters.chain
  if (filters?.type) params.type = filters.type
  if (filters?.featured !== undefined) params.featured = String(filters.featured)
  if (filters?.tokenIn) params.tokenIn = filters.tokenIn
  if (filters?.tokenOut) params.tokenOut = filters.tokenOut

  return useQuery({
    queryKey: ['strategies', params],
    queryFn: () => api.get<StrategiesResponse>('strategies', params),
    select: (data) => data.strategies,
    staleTime: 5 * 60 * 1000,
  })
}

export function useFeaturedStrategies() {
  return useQuery({
    queryKey: ['strategies', 'featured'],
    queryFn: () => api.get<StrategiesResponse>('strategies/featured'),
    select: (data) => data.strategies,
    staleTime: 5 * 60 * 1000,
  })
}

export function useStrategy(hash?: string) {
  return useQuery({
    queryKey: ['strategy', hash],
    queryFn: () => api.get<StrategyDetailResponse>(`strategies/${hash}`),
    select: (data) => data.strategy,
    enabled: !!hash,
    staleTime: 5 * 60 * 1000,
  })
}

export function useStrategyStats(hash?: string) {
  return useQuery({
    queryKey: ['strategy-stats', hash],
    queryFn: () => api.get<StrategyStatsResponse>(`strategies/${hash}/stats`),
    select: (data) => data.stats,
    enabled: !!hash,
    staleTime: 5 * 60 * 1000,
  })
}
