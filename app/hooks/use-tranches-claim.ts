import { useState, useCallback } from 'react'
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import {
  TRANCHES_HOOK,
  TRANCHES_HOOK_ABI,
  TRANCHES_POOL_KEY,
} from '@/lib/contracts'

type ClaimStep = 'idle' | 'claiming' | 'withdrawing0' | 'withdrawing1' | 'confirming' | 'done' | 'error'

export function useTranchesClaim() {
  const [step, setStep] = useState<ClaimStep>('idle')
  const [error, setError] = useState<string | null>(null)
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()

  const { writeContractAsync } = useWriteContract()
  const { data: receipt } = useWaitForTransactionReceipt({ hash: txHash })

  if (receipt && step === 'confirming') {
    setStep('done')
  }

  const execute = useCallback(async () => {
    setError(null)

    try {
      // Step 1: Claim — moves pending fees to claimable
      setStep('claiming')
      await writeContractAsync({
        address: TRANCHES_HOOK,
        abi: TRANCHES_HOOK_ABI,
        functionName: 'claimFees',
        args: [TRANCHES_POOL_KEY],
      })

      // Step 2: Withdraw currency0
      setStep('withdrawing0')
      await writeContractAsync({
        address: TRANCHES_HOOK,
        abi: TRANCHES_HOOK_ABI,
        functionName: 'withdrawFees',
        args: [TRANCHES_POOL_KEY.currency0],
      })

      // Step 3: Withdraw currency1
      setStep('withdrawing1')
      const hash = await writeContractAsync({
        address: TRANCHES_HOOK,
        abi: TRANCHES_HOOK_ABI,
        functionName: 'withdrawFees',
        args: [TRANCHES_POOL_KEY.currency1],
      })

      setStep('confirming')
      setTxHash(hash)
    } catch (err) {
      setStep('error')
      setError(err instanceof Error ? err.message : 'Claim failed')
    }
  }, [writeContractAsync])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setTxHash(undefined)
  }, [])

  return { execute, step, error, txHash, receipt, reset }
}
