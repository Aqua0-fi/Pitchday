import { useState, useCallback } from 'react'
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import {
  TRANCHES_ROUTER,
  TRANCHES_ROUTER_ABI,
  TRANCHES_POOL_KEY,
} from '@/lib/contracts'

type RemoveStep = 'idle' | 'removing' | 'confirming' | 'done' | 'error'

export function useTranchesRemove() {
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

    try {
      setStep('removing')
      const hash = await writeContractAsync({
        address: TRANCHES_ROUTER,
        abi: TRANCHES_ROUTER_ABI,
        functionName: 'removeLiquidity',
        args: [
          TRANCHES_POOL_KEY,
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
  }, [writeContractAsync])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setTxHash(undefined)
  }, [])

  return { execute, step, error, txHash, receipt, reset }
}
