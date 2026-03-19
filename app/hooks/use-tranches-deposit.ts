import { useState, useCallback } from 'react'
import { useWriteContract, usePublicClient, useAccount } from 'wagmi'
import { parseUnits } from 'viem'
import {
  TRANCHES_ROUTER,
  TRANCHES_ROUTER_ABI,
  TRANCHES_POOL_KEY,
  TRANCHES_POOLS,
  ERC20_ABI,
} from '@/lib/contracts'
import type { Address } from 'viem'

type DepositStep = 'idle' | 'approving' | 'depositing' | 'confirming' | 'done' | 'error'

export function useTranchesDeposit(hookAddress?: Address) {
  // Find the correct router for this hook
  const poolConfig = hookAddress
    ? TRANCHES_POOLS.find(p => p.hook.toLowerCase() === hookAddress.toLowerCase())
    : undefined
  const router = poolConfig?.router ?? TRANCHES_ROUTER
  const isAqua = poolConfig?.aqua ?? true

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

      if (isAqua) {
        // Aqua pool: amplify from SharedPool — no token approvals needed
        setStep('depositing')
        const hash = await writeContractAsync({
          address: router,
          abi: TRANCHES_ROUTER_ABI,
          functionName: 'addLiquidityFromSharedPool',
          args: [poolKey, tickLower, tickUpper, liquidity, amt0, amt1, tranche],
        })
        setStep('confirming')
        setTxHash(hash)
        await publicClient!.waitForTransactionReceipt({ hash })
      } else {
        // Traditional pool: direct deposit from wallet (needs token approvals)
        if (!account) throw new Error('Wallet not connected')

        // Approve token0 if needed
        if (amt0 > 0n) {
          const allowance0 = await publicClient!.readContract({
            address: TRANCHES_POOL_KEY.currency0,
            abi: ERC20_ABI,
            functionName: 'allowance',
            args: [account, router as Address],
          }) as bigint
          if (allowance0 < amt0) {
            setStep('approving')
            const maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935n
            const approveHash = await writeContractAsync({
              address: TRANCHES_POOL_KEY.currency0,
              abi: ERC20_ABI,
              functionName: 'approve',
              args: [router as Address, maxUint],
            })
            await publicClient!.waitForTransactionReceipt({ hash: approveHash })
          }
        }

        // Approve token1 if needed
        if (amt1 > 0n) {
          const allowance1 = await publicClient!.readContract({
            address: TRANCHES_POOL_KEY.currency1,
            abi: ERC20_ABI,
            functionName: 'allowance',
            args: [account, router as Address],
          }) as bigint
          if (allowance1 < amt1) {
            setStep('approving')
            const maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935n
            const approveHash = await writeContractAsync({
              address: TRANCHES_POOL_KEY.currency1,
              abi: ERC20_ABI,
              functionName: 'approve',
              args: [router as Address, maxUint],
            })
            await publicClient!.waitForTransactionReceipt({ hash: approveHash })
          }
        }

        // Direct deposit via addLiquidity (tokens come from wallet)
        setStep('depositing')
        const hash = await writeContractAsync({
          address: router,
          abi: TRANCHES_ROUTER_ABI,
          functionName: 'addLiquidity',
          args: [poolKey, tickLower, tickUpper, liquidity, amt0, amt1, tranche],
        })
        setStep('confirming')
        setTxHash(hash)
        await publicClient!.waitForTransactionReceipt({ hash })
      }

      setStep('done')
    } catch (err) {
      setStep('error')
      setError(err instanceof Error ? err.message : 'Deposit failed')
    }
  }, [writeContractAsync, publicClient, account, hookAddress, router, poolConfig, isAqua])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setTxHash(undefined)
  }, [])

  return { execute, step, error, txHash, reset, isAqua }
}
