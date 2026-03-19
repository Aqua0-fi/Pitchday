import { useReadContract, useReadContracts } from 'wagmi'
import { keccak256, encodePacked, encodeAbiParameters } from 'viem'
import { useWallet } from '@/contexts/wallet-context'
import {
  TRANCHES_HOOK,
  TRANCHES_HOOK_ABI,
  TRANCHES_POOL_KEY,
  TRANCHES_POOLS,
} from '@/lib/contracts'
import type { Address } from 'viem'

function computePoolId(hookAddress: Address, fee?: number, tickSpacing?: number): `0x${string}` {
  const poolConfig = TRANCHES_POOLS.find(p => p.hook.toLowerCase() === hookAddress.toLowerCase())
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'address' },
        { type: 'address' },
        { type: 'uint24' },
        { type: 'int24' },
        { type: 'address' },
      ],
      [
        TRANCHES_POOL_KEY.currency0,
        TRANCHES_POOL_KEY.currency1,
        fee ?? poolConfig?.fee ?? TRANCHES_POOL_KEY.fee,
        tickSpacing ?? poolConfig?.tickSpacing ?? TRANCHES_POOL_KEY.tickSpacing,
        hookAddress,
      ]
    )
  )
}

function computePositionKey(lp: `0x${string}`, hookAddress: Address): `0x${string}` {
  const poolId = computePoolId(hookAddress)
  return keccak256(encodePacked(['address', 'bytes32'], [lp, poolId]))
}

export function useTranchesPosition(hookAddress?: Address) {
  const hook = hookAddress ?? TRANCHES_HOOK
  const { address } = useWallet()
  const posKey = address ? computePositionKey(address as `0x${string}`, hook) : undefined

  // Read position data
  const { data: posData, isLoading: posLoading } = useReadContract({
    address: hook,
    abi: TRANCHES_HOOK_ABI,
    functionName: 'positions',
    args: posKey ? [posKey] : undefined,
    query: { enabled: !!posKey, refetchInterval: 10_000 },
  })

  // Read pending fees
  const poolConfig = TRANCHES_POOLS.find(p => p.hook.toLowerCase() === hook.toLowerCase())
  const poolKey = {
    ...TRANCHES_POOL_KEY,
    fee: poolConfig?.fee ?? TRANCHES_POOL_KEY.fee,
    tickSpacing: poolConfig?.tickSpacing ?? TRANCHES_POOL_KEY.tickSpacing,
    hooks: hook,
  }

  const { data: feesData, isLoading: feesLoading } = useReadContract({
    address: hook,
    abi: TRANCHES_HOOK_ABI,
    functionName: 'pendingFees',
    args: address ? [address as `0x${string}`, poolKey] : undefined,
    query: { enabled: !!address, refetchInterval: 10_000 },
  })

  // Read claimable balances
  const { data: claimableResults, isLoading: claimLoading } = useReadContracts({
    contracts: address ? [
      {
        address: hook,
        abi: TRANCHES_HOOK_ABI,
        functionName: 'claimableBalance',
        args: [address as `0x${string}`, TRANCHES_POOL_KEY.currency0],
      },
      {
        address: hook,
        abi: TRANCHES_HOOK_ABI,
        functionName: 'claimableBalance',
        args: [address as `0x${string}`, TRANCHES_POOL_KEY.currency1],
      },
    ] : [],
    query: { enabled: !!address, refetchInterval: 10_000 },
  })

  const isLoading = posLoading || feesLoading || claimLoading

  if (!posData || !address) {
    return { position: undefined, isLoading, hasPosition: false }
  }

  const [tranche, amount, depositBlock, , , depositSqrtPriceX96] = posData as [number, bigint, bigint, bigint, bigint, bigint]
  const hasPosition = amount > 0n

  const [pending0, pending1] = (feesData as [bigint, bigint]) || [0n, 0n]
  const claimable0 = claimableResults?.[0]?.result as bigint | undefined
  const claimable1 = claimableResults?.[1]?.result as bigint | undefined

  return {
    position: {
      tranche: tranche as 0 | 1,
      amount,
      depositBlock,
      depositSqrtPriceX96,
      pendingFees: { token0: pending0, token1: pending1 },
      claimable: { token0: claimable0 ?? 0n, token1: claimable1 ?? 0n },
    },
    isLoading,
    hasPosition,
  }
}
