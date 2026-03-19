import { useState, useCallback } from 'react'
import { parseUnits } from 'viem'
import type { Address } from 'viem'
import { useWriteContract, useWaitForTransactionReceipt, useAccount } from 'wagmi'
import { SWAP_VM_ROUTER, V4_ROUTER_ABI, ERC20_ABI } from '@/lib/contracts'
import { useSwapRouter } from './use-swap-router'
import type { V4Pool } from '@/lib/v4-api'

export type SwapStep =
  | 'idle'
  | 'approving'
  | 'swapping'
  | 'confirming'
  | 'done'
  | 'error'

interface ExecuteSwapParams {
  pool: V4Pool
  tokenIn: string
  tokenOut: string
  amountIn: string       // human-readable
  decimalsIn: number
  slippageBps: number    // e.g. 50 = 0.5%
}

export function useExecuteSwap(owner?: string) {
  const [step, setStep] = useState<SwapStep>('idle')
  const [error, setError] = useState<string | null>(null)
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>()

  const { chainId } = useAccount()
  const { data: routeAddress } = useSwapRouter(chainId)
  const routerTarget = routeAddress || SWAP_VM_ROUTER

  const { writeContractAsync } = useWriteContract()
  const { data: receipt, isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash: txHash,
  })

  // When receipt arrives, mark done
  if (receipt && step === 'confirming') {
    setStep('done')
  }

  const execute = useCallback(async (params: ExecuteSwapParams) => {
    const { pool, tokenIn, amountIn, decimalsIn } = params
    setError(null)
    setTxHash(undefined)

    try {
      const amountInRaw = parseUnits(amountIn, decimalsIn)
      const zeroForOne = tokenIn.toLowerCase() === pool.token0.address.toLowerCase()
      const isNativeToken = tokenIn === "0x0000000000000000000000000000000000000000"

      if (!isNativeToken) {
        // 1. Approve ERC20 spend
        setStep('approving')
        // Note: In production we'd check allowance first to save gas and clicks
        await writeContractAsync({
          address: tokenIn as Address,
          abi: ERC20_ABI,
          functionName: 'approve',
          args: [routerTarget, amountInRaw],
        })
      }

      // 2. Execute V4 Swap
      setStep('swapping')
      const hash = await writeContractAsync({
        address: routerTarget,
        abi: V4_ROUTER_ABI,
        functionName: 'swap',
        ...(isNativeToken ? { value: amountInRaw } : {}),
        args: [
          // key
          {
            currency0: pool.token0.address as Address,
            currency1: pool.token1.address as Address,
            fee: pool.fee,
            tickSpacing: pool.tickSpacing,
            hooks: pool.poolKey.hooks as Address,
          },
          // params
          {
            zeroForOne,
            amountSpecified: -amountInRaw, // negative = exact input
            sqrtPriceLimitX96: zeroForOne
              ? BigInt("4295128740")
              : BigInt("1461446703485210103287273052203988822378723970341")
          },
          // testSettings
          {
            takeClaims: false,
            settleUsingBurn: false,
          },
          // hookData
          '0x'
        ]
      })

      // 3. Wait for confirmation
      setStep('confirming')
      setTxHash(hash)

    } catch (err) {
      setStep('error')
      setError(err instanceof Error ? err.message : 'Swap failed')
    }
  }, [owner, writeContractAsync, routerTarget])

  const reset = useCallback(() => {
    setStep('idle')
    setError(null)
    setTxHash(undefined)
  }, [])

  return {
    execute,
    reset,
    step,
    error,
    txHash,
    receipt,
    isConfirming,
  }
}
