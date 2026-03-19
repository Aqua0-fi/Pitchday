import { useMemo } from 'react'
import { useStrategies, useFeaturedStrategies, useStrategy, type StrategyFilters } from './use-strategies'
import { useTokens } from './use-tokens'
import { mapApiStrategy } from '@/lib/api-mappers'
import type { Strategy } from '@/lib/types'

/** Fetches strategies from the API and maps them to frontend Strategy type */
export function useMappedStrategies(filters?: StrategyFilters) {
  const { data: apiStrategies, isLoading: strategiesLoading, error: strategiesError } = useStrategies(filters)
  const { data: tokens, isLoading: tokensLoading } = useTokens()

  const strategies = useMemo(() => {
    if (!apiStrategies || !tokens) return undefined
    return apiStrategies.map((s) => mapApiStrategy(s, tokens))
  }, [apiStrategies, tokens])

  return {
    data: strategies,
    isLoading: strategiesLoading || tokensLoading,
    error: strategiesError,
  }
}

/** Fetches featured strategies and maps them */
export function useMappedFeaturedStrategies() {
  const { data: apiStrategies, isLoading: strategiesLoading, error: strategiesError } = useFeaturedStrategies()
  const { data: tokens, isLoading: tokensLoading } = useTokens()

  const strategies = useMemo(() => {
    if (!apiStrategies || !tokens) return undefined
    return apiStrategies.map((s) => mapApiStrategy(s, tokens))
  }, [apiStrategies, tokens])

  return {
    data: strategies,
    isLoading: strategiesLoading || tokensLoading,
    error: strategiesError,
  }
}

/** Fetches a single strategy and maps it */
export function useMappedStrategy(hash?: string) {
  const { data: apiStrategy, isLoading: strategyLoading, error: strategyError } = useStrategy(hash)
  const { data: tokens, isLoading: tokensLoading } = useTokens()

  const strategy: Strategy | undefined = useMemo(() => {
    if (!apiStrategy || !tokens) return undefined
    return mapApiStrategy(apiStrategy, tokens)
  }, [apiStrategy, tokens])

  return {
    data: strategy,
    raw: apiStrategy,
    isLoading: strategyLoading || tokensLoading,
    error: strategyError,
  }
}
