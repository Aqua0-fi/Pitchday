import { describe, it, expect } from 'vitest'
import {
  chains,
  tokens,
  strategies,
  positions,
  transactions,
  userStats,
  earningsOverTime,
  liquidityByChain,
  apyComparison,
  strategyDetailData,
  userBalances,
} from '../mock-data'

describe('mock-data', () => {
  describe('chains', () => {
    it('has Base and Unichain', () => {
      expect(chains).toHaveLength(2)
      expect(chains.map(c => c.id)).toEqual(['base', 'unichain'])
    })

    it('each chain has required fields', () => {
      chains.forEach(chain => {
        expect(chain).toHaveProperty('id')
        expect(chain).toHaveProperty('name')
        expect(chain).toHaveProperty('logo')
        expect(chain).toHaveProperty('color')
      })
    })
  })

  describe('tokens', () => {
    it('has 6 tokens', () => {
      expect(tokens).toHaveLength(6)
    })

    it('each token has required fields', () => {
      tokens.forEach(token => {
        expect(token).toHaveProperty('symbol')
        expect(token).toHaveProperty('name')
        expect(token).toHaveProperty('logo')
        expect(token).toHaveProperty('decimals')
        expect(token).toHaveProperty('address')
        expect(typeof token.decimals).toBe('number')
      })
    })
  })

  describe('strategies', () => {
    it('has 3 strategies', () => {
      expect(strategies).toHaveLength(3)
    })

    it('each strategy has valid type', () => {
      const validTypes = ['constant-product', 'stable-swap']
      strategies.forEach(s => {
        expect(validTypes).toContain(s.type)
      })
    })

    it('each strategy has valid risk level', () => {
      const validRiskLevels = ['low', 'medium', 'high']
      strategies.forEach(s => {
        expect(validRiskLevels).toContain(s.riskLevel)
      })
    })

    it('each strategy references valid chains', () => {
      const chainIds = chains.map(c => c.id)
      strategies.forEach(s => {
        s.supportedChains.forEach(sc => {
          expect(chainIds).toContain(sc.id)
        })
      })
    })
  })

  describe('positions', () => {
    it('each position references a valid strategy', () => {
      const strategyIds = strategies.map(s => s.id)
      positions.forEach(p => {
        expect(strategyIds).toContain(p.strategyId)
      })
    })

    it('each position has numeric values', () => {
      positions.forEach(p => {
        expect(typeof p.deployedAmount).toBe('number')
        expect(typeof p.currentValue).toBe('number')
        expect(typeof p.earnings).toBe('number')
        expect(typeof p.apy).toBe('number')
      })
    })
  })

  describe('transactions', () => {
    it('each transaction has valid type', () => {
      const validTypes = ['deposit', 'swap', 'claim', 'withdraw']
      transactions.forEach(t => {
        expect(validTypes).toContain(t.type)
      })
    })

    it('each transaction has valid status', () => {
      const validStatuses = ['completed', 'pending', 'failed']
      transactions.forEach(t => {
        expect(validStatuses).toContain(t.status)
      })
    })
  })

  describe('userStats', () => {
    it('has expected fields', () => {
      expect(typeof userStats.totalLiquidityDeployed).toBe('number')
      expect(typeof userStats.totalEarnings).toBe('number')
      expect(typeof userStats.activePositions).toBe('number')
      expect(typeof userStats.averageApy).toBe('number')
    })
  })

  describe('chart data', () => {
    it('earningsOverTime has data points', () => {
      expect(earningsOverTime.length).toBeGreaterThan(0)
      earningsOverTime.forEach(point => {
        expect(point).toHaveProperty('date')
        expect(point).toHaveProperty('earnings')
      })
    })

    it('liquidityByChain references only Base and Unichain', () => {
      const validChains = ['Base', 'Unichain']
      liquidityByChain.forEach(item => {
        expect(validChains).toContain(item.chain)
      })
    })

    it('apyComparison has entries', () => {
      expect(apyComparison.length).toBeGreaterThan(0)
    })
  })

  describe('strategyDetailData', () => {
    it('has detail data for each strategy', () => {
      strategies.forEach(s => {
        expect(strategyDetailData).toHaveProperty(s.id)
      })
    })
  })

  describe('userBalances', () => {
    it('has entries for all token symbols', () => {
      tokens.forEach(t => {
        expect(userBalances).toHaveProperty(t.symbol)
        expect(typeof userBalances[t.symbol]).toBe('number')
      })
    })
  })
})
