import { useQuery } from '@tanstack/react-query'
import { fetchV4PoolsRegistry } from '@/lib/v4-api'
import { SWAP_VM_ROUTER } from '@/lib/contracts'

export function useSwapRouter(chainId: number | undefined) {
    return useQuery({
        queryKey: ['v4-router', chainId],
        queryFn: async () => {
            if (!chainId) return SWAP_VM_ROUTER;
            try {
                const data = await fetchV4PoolsRegistry(chainId);
                return (data.poolSwapTest as `0x${string}`) || SWAP_VM_ROUTER;
            } catch (err) {
                return SWAP_VM_ROUTER;
            }
        },
        enabled: !!chainId,
        refetchInterval: 15000,
    })
}
