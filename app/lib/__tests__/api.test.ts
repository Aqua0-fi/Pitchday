import { describe, it, expect } from 'vitest'
import {
  fetchStrategies,
  fetchStrategy,
  createStrategy,
  fetchPositions,
  fetchPosition,
  fetchTransactions,
  fetchUserStats,
  fetchTokens,
  fetchChains,
  fetchEarningsData,
  fetchLiquidityByChain,
  fetchApyComparison,
  fetchStrategyDetail,
  fetchUserBalances,
  validateBalance,
} from '../api'

describe('API functions', () => {
  describe('fetchStrategies', () => {
    it('returns an array of strategies', async () => {
      const result = await fetchStrategies()
      expect(Array.isArray(result)).toBe(true)
      expect(result.length).toBeGreaterThan(0)
      expect(result[0]).toHaveProperty('id')
      expect(result[0]).toHaveProperty('name')
      expect(result[0]).toHaveProperty('type')
    })
  })

  describe('fetchStrategy', () => {
    it('returns a strategy for a valid id', async () => {
      const result = await fetchStrategy('1')
      expect(result).not.toBeNull()
      expect(result!.id).toBe('1')
    })

    it('returns null for an invalid id', async () => {
      const result = await fetchStrategy('999')
      expect(result).toBeNull()
    })
  })

  describe('createStrategy', () => {
    it('returns a new strategy with generated id', async () => {
      const result = await createStrategy({
        type: 'stable-swap',
        tokenPair: ['USDC', 'USDT'],
        feeTier: 0.01,
        chains: ['base'],
        initialLiquidity: 0,
      })
      expect(result).toHaveProperty('id')
      expect(result).toHaveProperty('name')
      expect(result.type).toBe('stable-swap')
    })
  })

  describe('fetchPositions', () => {
    it('returns an array of positions', async () => {
      const result = await fetchPositions()
      expect(Array.isArray(result)).toBe(true)
      expect(result[0]).toHaveProperty('strategyId')
    })
  })

  describe('fetchPosition', () => {
    it('returns a position for a valid id', async () => {
      const result = await fetchPosition('1')
      expect(result).not.toBeNull()
      expect(result!.id).toBe('1')
    })

    it('returns null for an invalid id', async () => {
      const result = await fetchPosition('999')
      expect(result).toBeNull()
    })
  })

  describe('fetchTransactions', () => {
    it('returns an array of transactions', async () => {
      const result = await fetchTransactions()
      expect(Array.isArray(result)).toBe(true)
      expect(result[0]).toHaveProperty('type')
      expect(result[0]).toHaveProperty('status')
    })
  })

  describe('fetchUserStats', () => {
    it('returns user stats with expected shape', async () => {
      const result = await fetchUserStats()
      expect(result).toHaveProperty('totalLiquidityDeployed')
      expect(result).toHaveProperty('totalEarnings')
      expect(result).toHaveProperty('activePositions')
      expect(result).toHaveProperty('averageApy')
    })
  })

  describe('fetchTokens', () => {
    it('returns an array of tokens', async () => {
      const result = await fetchTokens()
      expect(Array.isArray(result)).toBe(true)
      expect(result[0]).toHaveProperty('symbol')
    })
  })

  describe('fetchChains', () => {
    it('returns an array of chains', async () => {
      const result = await fetchChains()
      expect(Array.isArray(result)).toBe(true)
      expect(result[0]).toHaveProperty('id')
    })
  })

  describe('fetchEarningsData', () => {
    it('returns chart data', async () => {
      const result = await fetchEarningsData()
      expect(Array.isArray(result)).toBe(true)
      expect(result[0]).toHaveProperty('date')
      expect(result[0]).toHaveProperty('earnings')
    })
  })

  describe('fetchLiquidityByChain', () => {
    it('returns liquidity data', async () => {
      const result = await fetchLiquidityByChain()
      expect(Array.isArray(result)).toBe(true)
      expect(result[0]).toHaveProperty('chain')
      expect(result[0]).toHaveProperty('value')
    })
  })

  describe('fetchApyComparison', () => {
    it('returns APY comparison data', async () => {
      const result = await fetchApyComparison()
      expect(Array.isArray(result)).toBe(true)
      expect(result[0]).toHaveProperty('strategy')
      expect(result[0]).toHaveProperty('apy')
    })
  })

  describe('fetchStrategyDetail', () => {
    it('returns detail for a valid strategy', async () => {
      const result = await fetchStrategyDetail('1')
      expect(result).not.toBeNull()
      expect(result).toHaveProperty('strategy')
      expect(result).toHaveProperty('volume24h')
    })

    it('returns null for an invalid strategy', async () => {
      const result = await fetchStrategyDetail('999')
      expect(result).toBeNull()
    })
  })

  describe('fetchUserBalances', () => {
    it('returns a record of balances', async () => {
      const result = await fetchUserBalances()
      expect(typeof result).toBe('object')
      expect(result).toHaveProperty('ETH')
      expect(typeof result.ETH).toBe('number')
    })
  })

  describe('validateBalance', () => {
    it('returns valid when amount is within balance', async () => {
      const result = await validateBalance('ETH', 1)
      expect(result.valid).toBe(true)
    })

    it('returns invalid when amount exceeds balance', async () => {
      const result = await validateBalance('ETH', 99999)
      expect(result.valid).toBe(false)
    })

    it('returns invalid for unknown token', async () => {
      const result = await validateBalance('UNKNOWN', 1)
      expect(result.valid).toBe(false)
    })
  })

})
