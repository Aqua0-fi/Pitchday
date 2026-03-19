import { useQuery } from '@tanstack/react-query'
import { fetchV4Pools, type V4Pool } from '@/lib/v4-api'
import { TRANCHES_POOLS, TRANCHES_POOL_KEY } from '@/lib/contracts'
import { keccak256, encodePacked } from 'viem'

// Generate hardcoded TrancheFi pools for all 3 fee tiers
const TRANCHEFI_POOLS: V4Pool[] = TRANCHES_POOLS.map((pool) => ({
    poolId: keccak256(
        encodePacked(
            ['address', 'address', 'uint24', 'int24', 'address'],
            [
                TRANCHES_POOL_KEY.currency0,
                TRANCHES_POOL_KEY.currency1,
                pool.fee,
                pool.tickSpacing,
                pool.hook,
            ]
        )
    ),
    poolKey: {
        currency0: TRANCHES_POOL_KEY.currency0,
        currency1: TRANCHES_POOL_KEY.currency1,
        fee: pool.fee,
        tickSpacing: pool.tickSpacing,
        hooks: pool.hook,
    },
    label: `TrancheFi ${pool.label} (${(pool.fee / 10000).toFixed(2)}%)`,
    token0: { address: TRANCHES_POOL_KEY.currency0, symbol: 'mUSDC', decimals: 18 },
    token1: { address: TRANCHES_POOL_KEY.currency1, symbol: 'mWETH', decimals: 18 },
    currentTick: 76013,
    currentPrice: 2000,
    sqrtPriceX96: '3543191142285914378072636784640',
    fee: pool.fee,
    tickSpacing: pool.tickSpacing,
    aggregatedRanges: [],
}))

export function useV4Pools(chainId: number | undefined) {
    return useQuery({
        queryKey: ['v4-pools', chainId],
        queryFn: async () => {
            try {
                const pools = await fetchV4Pools(chainId!)
                // Merge TrancheFi pools if not already present (Unichain Sepolia)
                if (chainId === 1301) {
                    for (const tPool of TRANCHEFI_POOLS) {
                        const exists = pools.some(
                            (p) => p.poolKey.hooks.toLowerCase() === tPool.poolKey.hooks.toLowerCase()
                                && p.poolKey.fee === tPool.poolKey.fee
                        )
                        if (!exists) pools.push(tPool)
                    }
                }
                return pools
            } catch {
                // Backend unavailable — return TrancheFi pools as fallback
                if (chainId === 1301) return [...TRANCHEFI_POOLS]
                return []
            }
        },
        enabled: !!chainId,
        refetchInterval: 15000,
    })
}
