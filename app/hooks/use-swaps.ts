import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { SwapsResponse } from '@/lib/api-types'

export function useSwapHistory(wallet?: string) {
  return useQuery({
    queryKey: ['swap-history', wallet],
    queryFn: () => api.get<SwapsResponse>(`swaps/history/${wallet}`),
    select: (data) => data.swaps,
    enabled: !!wallet,
    staleTime: 30 * 1000,
  })
}

export function useRecentSwaps() {
  return useQuery({
    queryKey: ['swaps', 'recent'],
    queryFn: () => api.get<SwapsResponse>('swaps/recent'),
    select: (data) => data.swaps,
    staleTime: 30 * 1000,
  })
}
