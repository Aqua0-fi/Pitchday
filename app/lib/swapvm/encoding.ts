import type { Address } from 'viem'

// SwapVM opcodes (from Opcodes.sol — index in _opcodes() after assembly skip)
export const OPCODE_DYNAMIC_BALANCES = 0x12 // 18: Balances._dynamicBalancesXD
export const OPCODE_FLAT_FEE_IN = 0x26      // 38: Fee._flatFeeAmountInXD
export const OPCODE_XYC_SWAP = 0x16         // 22: XYCSwap._xycSwapXD
export const OPCODE_PEGGED_SWAP = 0x2c      // 44: PeggedSwap._peggedSwapGrowPriceRange2D

/** Encode a single SwapVM instruction: [opcode: 1 byte][argsLength: 1 byte][args: N bytes] */
export function encodeInstruction(opcode: number, argsHex: string): string {
  const argsLength = argsHex.length / 2
  return toUint8Hex(opcode) + toUint8Hex(argsLength) + argsHex
}

/**
 * Encode Balances args (BalancesArgsBuilder.build):
 *   [tokenCount: uint16][token0: 20 bytes][token1: 20 bytes][balance0: uint256][balance1: uint256]
 */
export function encodeBalancesArgs(
  token0: Address,
  token1: Address,
  balance0: bigint,
  balance1: bigint,
): string {
  return (
    toUint16Hex(2) +
    stripPrefix(token0).toLowerCase() +
    stripPrefix(token1).toLowerCase() +
    toUint256Hex(balance0) +
    toUint256Hex(balance1)
  )
}

/** Encode Fee args (FeeArgsBuilder.buildFlatFee): [feeBps: uint32] */
export function encodeFeeArgs(feeBps: number): string {
  return toUint32Hex(feeBps)
}

/**
 * Encode PeggedSwap args (PeggedSwapArgsBuilder.build):
 *   [x0: uint256][y0: uint256][linearWidth: uint256][rateLt: uint256][rateGt: uint256]
 * Total: 160 bytes
 */
export function encodePeggedSwapArgs(
  x0: bigint,
  y0: bigint,
  linearWidth: bigint,
  rateLt: bigint,
  rateGt: bigint,
): string {
  return (
    toUint256Hex(x0) +
    toUint256Hex(y0) +
    toUint256Hex(linearWidth) +
    toUint256Hex(rateLt) +
    toUint256Hex(rateGt)
  )
}

/**
 * Sort tokens by address (ascending). Required for StableSwap.
 * Mirrors Solidity: token0 < token1 ? (token0, token1) : (token1, token0)
 */
export function sortTokens(
  token0: Address,
  balance0: bigint,
  token1: Address,
  balance1: bigint,
): { tokenLt: Address; tokenGt: Address; balanceLt: bigint; balanceGt: bigint } {
  if (token0.toLowerCase() < token1.toLowerCase()) {
    return { tokenLt: token0, tokenGt: token1, balanceLt: balance0, balanceGt: balance1 }
  }
  return { tokenLt: token1, tokenGt: token0, balanceLt: balance1, balanceGt: balance0 }
}

/**
 * Calculate rate multipliers for StableSwap given token addresses and decimals.
 * Normalizes both tokens to the same precision by scaling the higher-decimal token up.
 *
 * After sorting by address:
 *   rateLt = 10^(decimalsLt - min(decimalsLt, decimalsGt))
 *   rateGt = 10^(decimalsGt - min(decimalsLt, decimalsGt))
 *
 * Examples:
 *   DAI(18)/USDC(6): rateLt=1e12, rateGt=1
 *   WETH(18)/stETH(18): rateLt=1, rateGt=1
 */
export function calculateRates(
  token0: Address,
  token0Decimals: number,
  token1: Address,
  token1Decimals: number,
): { rateLt: bigint; rateGt: bigint } {
  const isToken0Lt = token0.toLowerCase() < token1.toLowerCase()
  const decimalsLt = isToken0Lt ? token0Decimals : token1Decimals
  const decimalsGt = isToken0Lt ? token1Decimals : token0Decimals
  const minDecimals = Math.min(decimalsLt, decimalsGt)
  return {
    rateLt: BigInt("1" + "0".repeat(decimalsLt - minDecimals)),
    rateGt: BigInt("1" + "0".repeat(decimalsGt - minDecimals)),
  }
}

// --- Hex encoding helpers (abi.encodePacked equivalents) ---

function stripPrefix(hex: string): string {
  return hex.startsWith('0x') ? hex.slice(2) : hex
}

function toUint8Hex(value: number): string {
  return value.toString(16).padStart(2, '0')
}

function toUint16Hex(value: number): string {
  return value.toString(16).padStart(4, '0')
}

function toUint32Hex(value: number): string {
  return value.toString(16).padStart(8, '0')
}

export function toUint256Hex(value: bigint): string {
  return value.toString(16).padStart(64, '0')
}
