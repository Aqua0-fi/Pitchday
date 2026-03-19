import { useReadContracts } from 'wagmi'
import { keccak256, encodePacked, encodeAbiParameters, parseAbiParameters, type Address } from 'viem'
import { POOL_MANAGER, TRANCHES_POOL_KEY } from '@/lib/contracts'

// PoolManager stores pool state in a mapping at slot 6:
//   mapping(PoolId => Pool.State) pools
// Pool.State layout:
//   slot+0: sqrtPriceX96 (uint160) | tick (int24) | protocolFee (uint24) | lpFee (uint24)
//   slot+1: liquidity (uint128)

const POOL_MANAGER_ABI = [
  {
    name: 'extsload',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'slot', type: 'bytes32' }],
    outputs: [{ name: 'value', type: 'bytes32' }],
  },
] as const

function computePoolId(key: typeof TRANCHES_POOL_KEY): `0x${string}` {
  // PoolId = keccak256(abi.encode(PoolKey)) — must use abi.encode, NOT encodePacked
  const encoded = encodeAbiParameters(
    parseAbiParameters('address, address, uint24, int24, address'),
    [key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks]
  )
  return keccak256(encoded)
}

// Get the storage slot for a pool's state in PoolManager
function getPoolSlot0Key(poolId: `0x${string}`): `0x${string}` {
  // pools mapping is at slot 6: keccak256(abi.encode(poolId, 6))
  return keccak256(encodeAbiParameters(
    parseAbiParameters('bytes32, uint256'),
    [poolId, 6n]
  ))
}

export function useTranchesPoolLiquidity() {
  const poolId = computePoolId(TRANCHES_POOL_KEY)
  const slot0Key = getPoolSlot0Key(poolId)
  // liquidity is at slot0Key + 1
  const liquiditySlot = keccak256(
    encodePacked(['bytes32'], [slot0Key])
  )

  // Actually, Pool.State slots are sequential: slot0Key is the base, slot0Key+1 is liquidity
  // We need to increment the slot by 1
  const slot0KeyBigInt = BigInt(slot0Key)
  const liquiditySlotHex = `0x${(slot0KeyBigInt + 1n).toString(16).padStart(64, '0')}` as `0x${string}`

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: POOL_MANAGER,
        abi: POOL_MANAGER_ABI,
        functionName: 'extsload',
        args: [slot0Key],
      },
      {
        address: POOL_MANAGER,
        abi: POOL_MANAGER_ABI,
        functionName: 'extsload',
        args: [liquiditySlotHex],
      },
    ],
    query: { refetchInterval: 10_000 },
  })

  if (!data || data.some(d => d.status === 'failure')) {
    return { poolId, currentTick: 0, sqrtPriceX96: '0', realLiquidity: '0', isLoading, error }
  }

  const slot0Raw = data[0].result as `0x${string}`
  const liquidityRaw = data[1].result as `0x${string}`

  // Parse slot0: sqrtPriceX96 (160 bits) | tick (24 bits) | protocolFee (24 bits) | lpFee (24 bits)
  // Layout in 256 bits (right-aligned):
  //   bits [255..96] = sqrtPriceX96 (uint160)
  //   bits [95..72]  = tick (int24)
  //   bits [71..48]  = protocolFee (uint24)
  //   bits [47..24]  = lpFee (uint24)
  const slot0BigInt = BigInt(slot0Raw)
  const sqrtPriceX96 = slot0BigInt >> 96n
  const tickRaw = Number((slot0BigInt >> 72n) & 0xFFFFFFn)
  const currentTick = tickRaw >= 0x800000 ? tickRaw - 0x1000000 : tickRaw // sign extend int24

  // Parse liquidity (uint128 — lower 128 bits of the slot)
  const liquidityBigInt = BigInt(liquidityRaw) & ((1n << 128n) - 1n)
  const realLiquidity = liquidityBigInt.toString()

  return {
    poolId,
    currentTick,
    sqrtPriceX96: sqrtPriceX96.toString(),
    realLiquidity,
    isLoading,
    error,
  }
}
