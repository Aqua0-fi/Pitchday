import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api-client'
import { BACKEND_CHAIN_IDS } from '@/lib/contracts'

export interface SharedBalance {
    token: string
    freeBalance: string
    walletBalance: string
    earnedFees: string
}

export function useSharedBalances(chainId: number | undefined, address: string | undefined, tokens: string[]) {
    return useQuery({
        queryKey: ['shared-balances', chainId, address, tokens.join(',')],
        queryFn: async () => {
            if (!chainId || !address || tokens.length === 0) return []

            const backendChainId = BACKEND_CHAIN_IDS[chainId] ?? 696969
            const { balances } = await api.get<{ balances: SharedBalance[] }>(
                `v4/lp/balances/${address}?chainId=${backendChainId}&tokens=${tokens.join(',')}`
            )
            return balances
        },
        enabled: !!chainId && !!address && tokens.length > 0,
        refetchInterval: 10000,
    })
}
