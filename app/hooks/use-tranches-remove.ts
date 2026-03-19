import { useState, useCallback } from 'react'
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import {
  TRANCHES_ROUTER,
  TRANCHES_ROUTER_ABI,
  TRANCHES_POOL_KEY,
  TRANCHES_POOLS,
} from '@/lib/contracts'
import type { Address } from 'viem'

type RemoveStep = 'idle' | 'removing' | 'confirming' | 'done' | 'error'

export function useTranchesRemove(hookAddress?: Address) {
  const poolConfig = hookAddress
    ? TRANCHES_POOLS.find(p => p.hook.toLowerCase() === hookAddress.toLowerCase())
    : undefined
  const router = poolConfig?.router ?? TRANCHES_ROUTER

  const [step, setStep] = useState<RemoveStep>('idle')
  const [error, setError] = useState<string | null>(null)
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()

  const { writeContractAsync } = useWriteContract()
  const { data: receipt } = useWaitForTransactionReceipt({ hash: txHash })

  if (receipt && step === 'confirming') {
    setStep('done')
  }

  const execute = useCallback(async (params: {
    tickLower?: number
    tickUpper?: number
    amount0Initial: bigint
    amount1Initial: bigint
  }) => {
    setError(null)
    const { tickLower = -120, tickUpper = 120, amount0Initial, amount1Initial } = params

    const poolKey = {
      ...TRANCHES_POOL_KEY,
      fee: poolConfig?.fee ?? TRANCHES_POOL_KEY.fee,
      tickSpacing: poolConfig?.tickSpacing ?? TRANCHES_POOL_KEY.tickSpacing,
      hooks: (hookAddress ?? TRANCHES_POOL_KEY.hooks) as Address,
    }

    try {
      setStep('removing')
      const hash = await writeContractAsync({
        address: router as Address,
        abi: TRANCHES_ROUTER_ABI,
        functionName: 'removeLiquidity',
        args: [
          poolKey,
          tickLower,
          tickUpper,
          amount0Initial,
          amount1Initial,
        ],
      })

      setStep('confirming')
      setTxHash(hash)
    } catch (err) {
      setStep('error')
      setError(err instanceof Error ? err.message : 'Removal failed')
    }
  }, [writeContractAsync, hookAddress, router, poolConfig])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setTxHash(undefined)
  }, [])

  return { execute, step, error, txHash, receipt, reset }
}
