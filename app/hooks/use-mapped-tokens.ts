import { useCallback, useMemo } from 'react'
import { useTokens } from './use-tokens'
import { useChains } from './use-chains'
import { useV4Pools } from './use-v4-pools'
import { getTokenLogo, getChainById } from '@/lib/token-logos'
import type { Token, Chain } from '@/lib/types'

/**
 * Returns real API tokens mapped to the frontend `Token` type.
 * Falls back to an empty array while loading.
 *
 * When no `chain` filter is supplied the API returns every token across
 * every chain, so USDC may appear twice.  We deduplicate by symbol for
 * UI display and expose `resolveAddress(symbol, chain)` so callers can
 * look up the chain-specific address when building deploy params.
 */
export function useMappedTokens(chain?: string) {
  const { data: apiTokens, isLoading: tokensLoading, error } = useTokens(chain)
  const isLocal = chain === 'local'
  const isUnichain = chain === 'unichain-sepolia' || chain === 'unichain'
  const usePoolTokens = isLocal || isUnichain
  const poolChainId = isLocal ? 696969 : isUnichain ? 1301 : undefined
  const { data: v4Pools, isLoading: poolsLoading } = useV4Pools(poolChainId)

  const isLoading = usePoolTokens ? poolsLoading : tokensLoading

  const tokens: Token[] = useMemo(() => {
    if (usePoolTokens) {
      if (!v4Pools) return []
      const seen = new Set<string>()
      const out: Token[] = []

      const getLogo = (symbol: string) => {
        const cleanSymbol = symbol.replace(/^m/, '');
        if (cleanSymbol === 'WBTC') return '/crypto/BTC.png';
        if (cleanSymbol === 'WETH') return '/crypto/ETH.png';
        return `/crypto/${cleanSymbol}.png`;
      };

      for (const p of v4Pools) {
        if (!seen.has(p.token0.symbol)) {
          seen.add(p.token0.symbol)
          out.push({
            symbol: p.token0.symbol,
            name: p.token0.symbol,
            logo: getLogo(p.token0.symbol),
            decimals: p.token0.decimals,
            address: p.token0.address,
          })
        }
        if (!seen.has(p.token1.symbol)) {
          seen.add(p.token1.symbol)
          out.push({
            symbol: p.token1.symbol,
            name: p.token1.symbol,
            logo: getLogo(p.token1.symbol),
            decimals: p.token1.decimals,
            address: p.token1.address,
          })
        }
      }
      return out
    }

    if (!apiTokens) return []
    const seen = new Set<string>()
    const out: Token[] = []
    for (const t of apiTokens) {
      if (seen.has(t.symbol)) continue
      seen.add(t.symbol)
      out.push({
        symbol: t.symbol,
        name: t.name,
        logo: getTokenLogo(t.symbol, t.logoUrl),
        decimals: t.decimals,
        address: t.address,
      })
    }
    return out
  }, [apiTokens, v4Pools, usePoolTokens])

  /** Resolve the on-chain address for a token symbol on a specific chain. */
  const resolveAddress = useCallback(
    (symbol: string, targetChain: string): string | undefined => {
      if (targetChain === 'local' || targetChain === 'unichain-sepolia' || targetChain === 'unichain') {
        return tokens.find((t) => t.symbol === symbol)?.address
      }
      if (!apiTokens) return undefined
      return apiTokens.find((t) => t.symbol === symbol && t.chain === targetChain)?.address
    },
    [apiTokens, tokens],
  )

  return { data: tokens, isLoading, error, resolveAddress }
}

/**
 * Returns real API chains mapped to the frontend `Chain` type.
 * Falls back to the hardcoded chains while loading.
 */
export function useMappedChains() {
  const { data: apiChains, isLoading, error } = useChains()

  const chains: Chain[] = useMemo(() => {
    // Always include Unichain Sepolia as primary chain for demo
    const unichain = getChainById(1301)
    if (!apiChains) return [unichain]
    const mapped = apiChains.map((c) => getChainById(c.id))
    if (!mapped.some(c => c.id === 'unichain-sepolia' || c.id === 'unichain')) {
      mapped.unshift(unichain)
    }
    return mapped
  }, [apiChains])

  return { data: chains, isLoading, error }
}
