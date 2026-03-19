import type { Address, Hex } from 'viem'
import {
  OPCODE_DYNAMIC_BALANCES,
  OPCODE_FLAT_FEE_IN,
  OPCODE_PEGGED_SWAP,
  encodeInstruction,
  encodeBalancesArgs,
  encodeFeeArgs,
  encodePeggedSwapArgs,
  sortTokens,
} from './encoding'

export interface StableSwapParams {
  token0: Address
  token1: Address
  balance0: bigint
  balance1: bigint
  linearWidth: bigint // A parameter scaled by 1e27 (e.g. 0.8e27 for A=0.8)
  rateLt: bigint      // Rate multiplier for lower-address token
  rateGt: bigint      // Rate multiplier for higher-address token
  feeBps: number      // Fee in basis points (5 = 0.05%). Max 1e9.
}

/**
 * Builds a SwapVM bytecode program for a StableSwap (PeggedSwap) AMM strategy.
 *
 * Replicates the Solidity logic from ExportTemplates.s.sol:_buildStableSwapProgram.
 * Optimized for pegged assets (stablecoins, wrapped tokens) with ~5x less slippage
 * than Constant Product for same-peg swaps.
 *
 * The program consists of 3 instructions:
 *   1. DynamicBalances — initializes token balances (tokens sorted by address)
 *   2. FlatFeeAmountIn — deducts fee from amountIn before swap
 *   3. PeggedSwap — executes StableSwap curve math
 */
export function buildStableSwapProgram(params: StableSwapParams): Hex {
  // Sort tokens by address (lower first) — required by PeggedSwap
  const { tokenLt, tokenGt, balanceLt, balanceGt } = sortTokens(
    params.token0,
    params.balance0,
    params.token1,
    params.balance1,
  )

  // Compute PeggedSwap normalized reserves
  const x0 = balanceLt * params.rateLt
  const y0 = balanceGt * params.rateGt

  const balancesArgs = encodeBalancesArgs(tokenLt, tokenGt, balanceLt, balanceGt)
  const feeArgs = encodeFeeArgs(params.feeBps)
  const peggedArgs = encodePeggedSwapArgs(x0, y0, params.linearWidth, params.rateLt, params.rateGt)

  return `0x${
    encodeInstruction(OPCODE_DYNAMIC_BALANCES, balancesArgs)
  }${
    encodeInstruction(OPCODE_FLAT_FEE_IN, feeArgs)
  }${
    encodeInstruction(OPCODE_PEGGED_SWAP, peggedArgs)
  }` as Hex
}
