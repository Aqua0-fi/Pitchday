import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { RebalancerConfigResponse, RebalancerOperationsResponse, RebalancerPendingResponse } from '@/lib/api-types'

export function useRebalancerConfig(wallet?: string) {
  return useQuery({
    queryKey: ['rebalancer-config', wallet],
    queryFn: () => api.get<RebalancerConfigResponse>(`rebalancer/${wallet}`),
    select: (data) => data.config,
    enabled: !!wallet,
    staleTime: 60 * 1000,
  })
}

export function useRebalancerOperations(lpAccount?: string) {
  return useQuery({
    queryKey: ['rebalancer-operations', lpAccount],
    queryFn: () => api.get<RebalancerOperationsResponse>(`rebalancer/${lpAccount}/operations`),
    select: (data) => data.operations,
    enabled: !!lpAccount,
    staleTime: 30 * 1000,
  })
}

export function usePendingRebalances(lpAccount?: string) {
  return useQuery({
    queryKey: ['rebalancer-pending', lpAccount],
    queryFn: () => api.get<RebalancerPendingResponse>(`rebalancer/${lpAccount}/pending`),
    select: (data) => data.pendingOperations,
    enabled: !!lpAccount,
    staleTime: 30 * 1000,
  })
}
