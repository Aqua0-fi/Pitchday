import { useQuery } from '@tanstack/react-query'
import { fetchV4Pools, type V4Pool } from '@/lib/v4-api'
import { TRANCHES_HOOK, TRANCHES_POOL_KEY } from '@/lib/contracts'
import { keccak256, encodePacked } from 'viem'

// Hardcoded TrancheFi pool for Unichain Sepolia — always available without backend
const TRANCHEFI_POOL: V4Pool = {
    poolId: keccak256(
        encodePacked(
            ['address', 'address', 'uint24', 'int24', 'address'],
            [
                TRANCHES_POOL_KEY.currency0,
                TRANCHES_POOL_KEY.currency1,
                TRANCHES_POOL_KEY.fee,
                TRANCHES_POOL_KEY.tickSpacing,
                TRANCHES_POOL_KEY.hooks,
            ]
        )
    ),
    poolKey: {
        currency0: TRANCHES_POOL_KEY.currency0,
        currency1: TRANCHES_POOL_KEY.currency1,
        fee: TRANCHES_POOL_KEY.fee,
        tickSpacing: TRANCHES_POOL_KEY.tickSpacing,
        hooks: TRANCHES_POOL_KEY.hooks,
    },
    label: 'TrancheFi Senior/Junior',
    token0: { address: TRANCHES_POOL_KEY.currency0, symbol: 'mWETH', decimals: 18 },
    token1: { address: TRANCHES_POOL_KEY.currency1, symbol: 'mUSDC', decimals: 18 },
    currentTick: 76020,
    currentPrice: 2000,
    sqrtPriceX96: '3543191142285914245838491972061',
    fee: TRANCHES_POOL_KEY.fee,
    tickSpacing: TRANCHES_POOL_KEY.tickSpacing,
    aggregatedRanges: [],
}

export function useV4Pools(chainId: number | undefined) {
    return useQuery({
        queryKey: ['v4-pools', chainId],
        queryFn: async () => {
            try {
                const pools = await fetchV4Pools(chainId!)
                // Merge: add TrancheFi pool if not already present (Unichain Sepolia)
                if (chainId === 1301) {
                    const hasTrancheFi = pools.some(
                        (p) => p.poolKey.hooks.toLowerCase() === TRANCHES_HOOK.toLowerCase()
                    )
                    if (!hasTrancheFi) pools.push(TRANCHEFI_POOL)
                }
                return pools
            } catch {
                // Backend unavailable — return TrancheFi pool as fallback
                if (chainId === 1301) return [TRANCHEFI_POOL]
                return []
            }
        },
        enabled: !!chainId,
        refetchInterval: 15000,
    })
}
