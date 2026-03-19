import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import type { ApiUser, ApiUserPreferences } from '@/lib/api-types'

export function useUser(wallet?: string) {
  return useQuery({
    queryKey: ['user', wallet],
    queryFn: () => api.get<ApiUser>(`users/${wallet}`),
    enabled: !!wallet,
    staleTime: 5 * 60 * 1000,
    retry: false,
  })
}

export function useUserPreferences(wallet?: string) {
  return useQuery({
    queryKey: ['user-preferences', wallet],
    queryFn: () => api.get<ApiUserPreferences>(`users/${wallet}/preferences`),
    enabled: !!wallet,
    staleTime: 5 * 60 * 1000,
    retry: false,
  })
}
