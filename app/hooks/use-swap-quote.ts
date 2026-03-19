"use client"

import { useQuery } from '@tanstack/react-query'
import { parseUnits, formatUnits } from 'viem'
import type { V4Pool } from '@/lib/v4-api'
import { fetchSwapQuote, type SwapQuoteApiResult } from '@/lib/v4-api'
import { BACKEND_CHAIN_IDS } from '@/lib/contracts'

export interface SwapQuoteResult {
  amountOut: string        // human-readable
  amountOutRaw: string     // uint256 string
  executionPrice: number
  // JIT breakdown from exact simulation
  apiResult?: SwapQuoteApiResult
  isExactSimulation: boolean
}

/**
 * Swap quote using exact on-chain simulation via Aqua0QuoteHelper.
 * Falls back to tick-based estimate if the backend quote fails.
 */
export function useSwapQuote(
  pool: V4Pool | undefined,
  tokenIn?: string,
  amountIn?: string,
  decimalsIn?: number,
  decimalsOut?: number,
  backendChainId?: number,
) {
  const hasInputs = !!pool && !!tokenIn && !!amountIn && Number(amountIn) > 0 &&
    decimalsIn !== undefined && decimalsOut !== undefined

  return useQuery({
    queryKey: ['v4-quote-exact', pool?.poolId, tokenIn, amountIn, backendChainId],
    queryFn: async (): Promise<SwapQuoteResult> => {
      const isToken0 = tokenIn!.toLowerCase() === pool!.token0.address.toLowerCase()
      const zeroForOne = isToken0
      const amountInRaw = parseUnits(amountIn!, decimalsIn!)

      // Try exact on-chain simulation first
      if (backendChainId) {
        try {
          const apiResult = await fetchSwapQuote(
            backendChainId,
            pool!.poolId,
            zeroForOne,
            amountInRaw.toString(),
          )

          // totalAmountOut is positive for exact-input swaps (amount we receive)
          const rawOut = BigInt(apiResult.totalAmountOut)
          const absOut = rawOut < 0n ? -rawOut : rawOut
          const amountOutStr = formatUnits(absOut, decimalsOut!)
          const executionPrice = Number(amountOutStr) / Number(amountIn!)

          return {
            amountOut: Number(amountOutStr).toFixed(Math.min(decimalsOut!, 6)),
            amountOutRaw: absOut.toString(),
            executionPrice,
            apiResult,
            isExactSimulation: true,
          }
        } catch (err) {
          // Backend quote failed – fall through to estimate
          console.warn('[useSwapQuote] Exact quote failed, using tick estimate:', err)
        }
      }

      // Fallback: tick-based price estimate
      const priceOf0In1 = Math.pow(1.0001, pool!.currentTick) *
        Math.pow(10, pool!.token0.decimals - pool!.token1.decimals)
      const executionPrice = isToken0 ? priceOf0In1 : (1 / priceOf0In1)
      const feeMultiplier = 1 - (pool!.fee / 1_000_000)
      const outVal = Number(amountIn) * executionPrice * feeMultiplier
      const amountOutStr = outVal.toFixed(Math.min(decimalsOut!, 6))
      const amountOutRaw = parseUnits(amountOutStr, decimalsOut!).toString()

      return {
        amountOut: amountOutStr,
        amountOutRaw,
        executionPrice,
        isExactSimulation: false,
      }
    },
    enabled: hasInputs,
    refetchInterval: 15 * 1000,
    staleTime: 5 * 1000,
  })
}
