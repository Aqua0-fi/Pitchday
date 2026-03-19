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
      // In Uniswap V4: price = 1.0001^tick = token0 per token1 (how much token0 for 1 token1)
      // With tick=76013: price ≈ 2000 means 1 mWETH (token1) = 2000 mUSDC (token0)
      const priceOf1In0 = Math.pow(1.0001, pool!.currentTick) *
        Math.pow(10, pool!.token0.decimals - pool!.token1.decimals)
      // If selling token0 (mUSDC): you get token1, so divide by price
      // If selling token1 (mWETH): you get token0, so multiply by price
      const executionPrice = isToken0 ? (1 / priceOf1In0) : priceOf1In0
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
