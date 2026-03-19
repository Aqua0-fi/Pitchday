import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { TokensResponse } from '@/lib/api-types'

export function useTokens(chain?: string) {
  return useQuery({
    queryKey: ['tokens', chain],
    queryFn: () => api.get<TokensResponse>('tokens', chain ? { chain } : undefined),
    select: (data) => data.tokens,
    staleTime: 10 * 60 * 1000, // 10 min
  })
}

export function useStablecoins(chain?: string) {
  return useQuery({
    queryKey: ['tokens', 'stablecoins', chain],
    queryFn: () => api.get<TokensResponse>('tokens/stablecoins', chain ? { chain } : undefined),
    select: (data) => data.tokens,
    staleTime: 10 * 60 * 1000,
  })
}
