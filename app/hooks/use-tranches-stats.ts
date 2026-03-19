import { useReadContract } from 'wagmi'
import { TRANCHES_HOOK, TRANCHES_HOOK_ABI, TRANCHES_POOL_KEY } from '@/lib/contracts'

export function useTranchesStats() {
  const { data, isLoading, error, refetch } = useReadContract({
    address: TRANCHES_HOOK,
    abi: TRANCHES_HOOK_ABI,
    functionName: 'getPoolStats',
    args: [TRANCHES_POOL_KEY],
    query: { refetchInterval: 10_000 },
  })

  if (!data) return { stats: undefined, isLoading, error, refetch }

  const [totalSenior, totalJunior, seniorFees, juniorFees, seniorAPY, seniorRatio] = data as [bigint, bigint, bigint, bigint, bigint, bigint]

  return {
    stats: {
      totalSenior,
      totalJunior,
      seniorFees,
      juniorFees,
      seniorAPY,    // in bips (e.g. 500 = 5%)
      seniorRatio,  // in bips (e.g. 7000 = 70%)
    },
    isLoading,
    error,
    refetch,
  }
}
