import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { ChainsResponse } from '@/lib/api-types'

export function useChains() {
  return useQuery({
    queryKey: ['chains'],
    queryFn: () => api.get<ChainsResponse>('chains'),
    select: (data) => data.chains,
    staleTime: 60 * 60 * 1000, // 1 hour — chains are static
  })
}
