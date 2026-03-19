import { strategies, positions, transactions, userStats, tokens, chains, earningsOverTime, liquidityByChain, apyComparison, strategyDetailData, userBalances } from './mock-data'
import type { Strategy, Position, Transaction, UserStats, Token, Chain, CreateStrategyForm } from './types'

// Simulate API delay
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))

// Strategies API
export async function fetchStrategies(): Promise<Strategy[]> {
  await delay(800)
  return strategies
}

export async function fetchStrategy(id: string): Promise<Strategy | null> {
  await delay(500)
  return strategies.find(s => s.id === id) || null
}

export async function createStrategy(form: CreateStrategyForm): Promise<Strategy> {
  await delay(1500)
  // Mock creating a new strategy
  const newStrategy: Strategy = {
    id: String(strategies.length + 1),
    name: `${form.tokenPair[0]}/${form.tokenPair[1]} Custom`,
    type: form.type,
    tokenPair: [tokens[0], tokens[1]],
    apy: Math.random() * 30 + 5,
    tvl: 0,
    riskLevel: form.type === 'stable-swap' ? 'low' : 'medium',
    supportedChains: chains.filter(c => form.chains.includes(c.id)),
    feeTier: form.feeTier,
    createdAt: new Date().toISOString(),
  }
  return newStrategy
}

// Positions API
export async function fetchPositions(): Promise<Position[]> {
  await delay(800)
  return positions
}

export async function fetchPosition(id: string): Promise<Position | null> {
  await delay(500)
  return positions.find(p => p.id === id) || null
}

// Transactions API
export async function fetchTransactions(): Promise<Transaction[]> {
  await delay(600)
  return transactions
}

// User stats API
export async function fetchUserStats(): Promise<UserStats> {
  await delay(400)
  return userStats
}

// Tokens and Chains API
export async function fetchTokens(): Promise<Token[]> {
  await delay(300)
  return tokens
}

export async function fetchChains(): Promise<Chain[]> {
  await delay(300)
  return chains
}

// Chart data API
export async function fetchEarningsData() {
  await delay(500)
  return earningsOverTime
}

export async function fetchLiquidityByChain() {
  await delay(500)
  return liquidityByChain
}

export async function fetchApyComparison() {
  await delay(500)
  return apyComparison
}

// Strategy detail API
export async function fetchStrategyDetail(id: string) {
  await delay(600)
  const strategy = strategies.find(s => s.id === id)
  const detail = strategyDetailData[id as keyof typeof strategyDetailData]
  if (!strategy || !detail) return null
  return { strategy, ...detail }
}

// User balances API
export async function fetchUserBalances() {
  await delay(300)
  return userBalances
}

// Validate balance API
export async function validateBalance(token: string, amount: number) {
  await delay(200)
  const balance = userBalances[token] || 0
  return { valid: amount <= balance, balance, requested: amount }
}


