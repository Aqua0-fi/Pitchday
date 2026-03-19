import { useState, useCallback } from 'react'
import { useWriteContract, usePublicClient, useAccount } from 'wagmi'
import { parseUnits } from 'viem'
import {
  TRANCHES_ROUTER,
  TRANCHES_ROUTER_ABI,
  TRANCHES_POOL_KEY,
  TRANCHES_POOLS,
} from '@/lib/contracts'
import type { Address } from 'viem'

type DepositStep = 'idle' | 'depositing' | 'confirming' | 'done' | 'error'

export function useTranchesDeposit(hookAddress?: Address) {
  // Find the correct router for this hook
  const poolConfig = hookAddress
    ? TRANCHES_POOLS.find(p => p.hook.toLowerCase() === hookAddress.toLowerCase())
    : undefined
  const router = poolConfig?.router ?? TRANCHES_ROUTER

  const [step, setStep] = useState<DepositStep>('idle')
  const [error, setError] = useState<string | null>(null)
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()

  const { writeContractAsync } = useWriteContract()
  const publicClient = usePublicClient()
  const { address: account } = useAccount()

  const execute = useCallback(async (params: {
    tranche: 0 | 1 // 0 = Senior, 1 = Junior
    amount0: string  // token0 amount (human-readable)
    amount1: string  // token1 amount (human-readable)
    tickLower?: number
    tickUpper?: number
  }) => {
    setError(null)
    const { tranche, amount0, amount1, tickLower = -120, tickUpper = 120 } = params

    const amt0 = parseUnits(amount0 || '0', 18)
    const amt1 = parseUnits(amount1 || '0', 18)

    if (amt0 === 0n && amt1 === 0n) {
      setStep('error')
      setError('Enter at least one token amount')
      return
    }

    // Liquidity = min of the two amounts (simple 1:1 pool heuristic)
    const liquidity = amt0 < amt1 ? amt0 : amt1 > 0n ? amt1 : amt0

    try {
      // Build pool key for this specific hook
      const poolKey = hookAddress ? {
        currency0: TRANCHES_POOL_KEY.currency0,
        currency1: TRANCHES_POOL_KEY.currency1,
        fee: poolConfig?.fee ?? TRANCHES_POOL_KEY.fee,
        tickSpacing: poolConfig?.tickSpacing ?? TRANCHES_POOL_KEY.tickSpacing,
        hooks: hookAddress,
      } : TRANCHES_POOL_KEY

      // Amplify from SharedPool — no token approvals needed!
      // Funds come from user's SharedPool freeBalance, not wallet.
      setStep('depositing')
      const hash = await writeContractAsync({
        address: router,
        abi: TRANCHES_ROUTER_ABI,
        functionName: 'addLiquidityFromSharedPool',
        args: [
          poolKey,
          tickLower,
          tickUpper,
          liquidity,
          amt0,
          amt1,
          tranche,
        ],
      })

      setStep('confirming')
      setTxHash(hash)
      await publicClient!.waitForTransactionReceipt({ hash })
      setStep('done')
    } catch (err) {
      setStep('error')
      setError(err instanceof Error ? err.message : 'Amplification failed')
    }
  }, [writeContractAsync, publicClient, account, hookAddress, router, poolConfig])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setTxHash(undefined)
  }, [])

  return { execute, step, error, txHash, reset }
}
