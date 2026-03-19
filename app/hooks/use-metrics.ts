import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { MetricsResponse, TvlResponse, VolumeResponse, FeesResponse } from '@/lib/api-types'

export function useMetrics() {
  return useQuery({
    queryKey: ['metrics'],
    queryFn: () => api.get<MetricsResponse>('metrics'),
    staleTime: 60 * 1000,
  })
}

export function useTvl() {
  return useQuery({
    queryKey: ['metrics', 'tvl'],
    queryFn: () => api.get<TvlResponse>('metrics/tvl'),
    staleTime: 60 * 1000,
  })
}

export function useVolume() {
  return useQuery({
    queryKey: ['metrics', 'volume'],
    queryFn: () => api.get<VolumeResponse>('metrics/volume'),
    staleTime: 60 * 1000,
  })
}

export function useFees() {
  return useQuery({
    queryKey: ['metrics', 'fees'],
    queryFn: () => api.get<FeesResponse>('metrics/fees'),
    staleTime: 60 * 1000,
  })
}
