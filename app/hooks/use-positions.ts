import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { PositionsResponse, PositionSummaryResponse, PositionHistoryResponse } from '@/lib/api-types'

export function usePositions(wallet?: string) {
  return useQuery({
    queryKey: ['positions', wallet],
    queryFn: () => api.get<PositionsResponse>(`positions/${wallet}`),
    enabled: !!wallet,
    staleTime: 30 * 1000,
  })
}

export function usePositionSummary(wallet?: string) {
  return useQuery({
    queryKey: ['position-summary', wallet],
    queryFn: () => api.get<PositionSummaryResponse>(`positions/${wallet}/summary`),
    select: (data) => data.summary,
    enabled: !!wallet,
    staleTime: 30 * 1000,
  })
}

export function usePositionHistory(wallet?: string) {
  return useQuery({
    queryKey: ['position-history', wallet],
    queryFn: () => api.get<PositionHistoryResponse>(`positions/${wallet}/history`),
    select: (data) => data.events,
    enabled: !!wallet,
    staleTime: 60 * 1000,
  })
}
