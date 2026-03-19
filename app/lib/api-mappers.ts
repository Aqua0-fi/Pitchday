import type { Strategy, StrategyType, RiskLevel, Token, Chain, Position, Transaction } from './types'
import type { ApiStrategy, ApiToken, ApiPosition, ApiSwap } from './api-types'
import { getTokenLogo, getChainById, getChainByName } from './token-logos'

/** Map backend strategy_type → frontend StrategyType */
export function mapStrategyType(backendType: string | null): StrategyType {
  switch (backendType) {
    case 'constant_product':
      return 'constant-product'
    case 'stable_swap':
    case 'stableswap':
      return 'stable-swap'
    default:
      return 'constant-product'
  }
}

/** Map backend risk_level → frontend RiskLevel */
function mapRiskLevel(level: string | null): RiskLevel {
  if (level === 'low' || level === 'medium' || level === 'high') return level
  return 'medium'
}

/** Resolve a token address to a frontend Token object using the token list */
export function resolveToken(address: string, tokens: ApiToken[]): Token {
  const found = tokens.find(
    (t) => t.address.toLowerCase() === address.toLowerCase(),
  )
  if (found) {
    return {
      symbol: found.symbol,
      name: found.name,
      logo: getTokenLogo(found.symbol, found.logoUrl),
      decimals: found.decimals,
      address: found.address,
    }
  }
  // Fallback for unknown tokens
  const short = `${address.slice(0, 6)}...${address.slice(-4)}`
  return {
    symbol: short,
    name: short,
    logo: '/crypto/ETH.png',
    decimals: 18,
    address,
  }
}

/** Map a backend ApiStrategy to a frontend Strategy */
export function mapApiStrategy(
  api: ApiStrategy,
  tokens: ApiToken[],
): Strategy {
  const tokenIn = resolveToken(api.tokenIn, tokens)
  const tokenOut = resolveToken(api.tokenOut, tokens)
  const chain = getChainById(api.chainId)

  // Build supported chains from backend array or fallback to primary chain
  const supportedChains: Chain[] =
    api.supportedChains && api.supportedChains.length > 0
      ? api.supportedChains.map((name) => {
          const entry = Object.entries(
            { base: 8453, unichain: 130, arbitrum: 42161 } as Record<string, number>,
          ).find(([k]) => k === name)
          return entry ? getChainById(entry[1]) : { id: name, name, logo: '/crypto/Base.png', color: '#888' }
        })
      : [chain]

  return {
    id: api.strategyHash,
    name: api.displayName || `${tokenIn.symbol}/${tokenOut.symbol}`,
    type: mapStrategyType(api.strategyType),
    tokenPair: [tokenIn, tokenOut],
    apy: api.apy24h ?? 0,
    tvl: api.tvlUsd ?? 0,
    riskLevel: mapRiskLevel(api.riskLevel),
    supportedChains,
    feeTier: api.feeBps / 100,
    createdAt: new Date(api.registeredAt * 1000).toISOString(),
  }
}

/** Map a backend ApiPosition to a frontend Position */
export function mapApiPosition(
  pos: ApiPosition,
  strategies: ApiStrategy[],
): Position {
  const strategy = strategies.find((s) => s.strategyHash === pos.strategyHash)
  const chain = getChainByName(pos.chain)

  return {
    id: pos.id,
    strategyId: pos.strategyHash,
    strategyName: strategy?.displayName || `Strategy ${pos.strategyHash.slice(0, 8)}`,
    deployedAmount: pos.depositedUsd,
    currentValue: pos.balanceUsd,
    earnings: pos.earnedFeesUsd,
    apy: 0, // Not available per-position from backend
    chains: [chain],
    createdAt: pos.createdAt,
  }
}

/** Map a backend ApiSwap to a frontend Transaction */
export function mapApiSwapToTransaction(
  swap: ApiSwap,
  tokens: ApiToken[],
): Transaction {
  const tokenIn = resolveToken(swap.tokenIn, tokens)
  const chain = getChainById(swap.chainId)

  return {
    id: swap.id,
    type: 'swap',
    status: 'completed',
    amount: parseFloat(swap.amountIn),
    token: tokenIn,
    chain,
    timestamp: new Date(swap.timestamp * 1000).toISOString(),
    hash: swap.txHash,
  }
}
