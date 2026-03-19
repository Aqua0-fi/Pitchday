import { useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { formatUnits } from 'viem'
import { ERC20_ABI, TRANCHES_SHARED_POOL } from '@/lib/contracts'

const SHARED_POOL_ABI = [
  {
    name: 'freeBalance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'token', type: 'address' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'earnedFees',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'user', type: 'address' },
      { name: 'token', type: 'address' },
    ],
    outputs: [{ type: 'uint256' }],
  },
] as const

export interface SharedBalance {
    token: string
    freeBalance: string
    walletBalance: string
    earnedFees: string
}

export function useSharedBalances(chainId: number | undefined, address: string | undefined, tokens: string[]) {
    const publicClient = usePublicClient()

    return useQuery({
        queryKey: ['shared-balances-onchain', chainId, address, tokens.join(',')],
        queryFn: async (): Promise<SharedBalance[]> => {
            if (!chainId || !address || tokens.length === 0 || !publicClient) return []

            const results: SharedBalance[] = []

            for (const token of tokens) {
                // Read wallet balance
                const walletBalance = await publicClient.readContract({
                    address: token as `0x${string}`,
                    abi: ERC20_ABI,
                    functionName: 'balanceOf',
                    args: [address as `0x${string}`],
                }) as bigint

                // Read freeBalance in SharedPool
                const freeBalance = await publicClient.readContract({
                    address: TRANCHES_SHARED_POOL,
                    abi: SHARED_POOL_ABI,
                    functionName: 'freeBalance',
                    args: [address as `0x${string}`, token as `0x${string}`],
                }) as bigint

                // Read earnedFees in SharedPool
                const earnedFees = await publicClient.readContract({
                    address: TRANCHES_SHARED_POOL,
                    abi: SHARED_POOL_ABI,
                    functionName: 'earnedFees',
                    args: [address as `0x${string}`, token as `0x${string}`],
                }) as bigint

                results.push({
                    token,
                    walletBalance: walletBalance.toString(),
                    freeBalance: freeBalance.toString(),
                    earnedFees: earnedFees.toString(),
                })
            }

            return results
        },
        enabled: !!chainId && !!address && tokens.length > 0 && !!publicClient,
        refetchInterval: 10000,
    })
}
