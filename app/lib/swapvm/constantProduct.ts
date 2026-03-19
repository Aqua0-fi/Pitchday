import type { Address, Hex } from 'viem'
import {
  OPCODE_DYNAMIC_BALANCES,
  OPCODE_FLAT_FEE_IN,
  OPCODE_XYC_SWAP,
  encodeInstruction,
  encodeBalancesArgs,
  encodeFeeArgs,
} from './encoding'

/**
 * Builds a SwapVM bytecode program for a Constant Product (x*y=k) AMM strategy.
 *
 * Replicates the Solidity logic from ExportTemplates.s.sol:_buildConstantProductProgram.
 * The program consists of 3 instructions:
 *   1. DynamicBalances — initializes token balances
 *   2. FlatFeeAmountIn — deducts fee from amountIn before swap
 *   3. XYCSwap — executes x*y=k swap math
 *
 * @param token0 - Address of first token
 * @param token1 - Address of second token
 * @param balance0 - Initial balance of token0 (in token's smallest unit)
 * @param balance1 - Initial balance of token1 (in token's smallest unit)
 * @param feeBps - Fee in basis points (30 = 0.3%, 100 = 1%). Max 1e9.
 * @returns Hex-encoded bytecode program
 */
export function buildConstantProductProgram(
  token0: Address,
  token1: Address,
  balance0: bigint,
  balance1: bigint,
  feeBps: number,
): Hex {
  const balancesArgs = encodeBalancesArgs(token0, token1, balance0, balance1)
  const feeArgs = encodeFeeArgs(feeBps)

  return `0x${
    encodeInstruction(OPCODE_DYNAMIC_BALANCES, balancesArgs)
  }${
    encodeInstruction(OPCODE_FLAT_FEE_IN, feeArgs)
  }${
    encodeInstruction(OPCODE_XYC_SWAP, '')
  }` as Hex
}
