// Chain types
export interface Chain {
  id: string
  name: string
  logo: string
  color: string
}

// Token types
export interface Token {
  symbol: string
  name: string
  logo: string
  decimals: number
  address: string
}

// Strategy types
export type StrategyType = 'constant-product' | 'stable-swap'
export type RiskLevel = 'low' | 'medium' | 'high'

export interface Strategy {
  id: string
  name: string
  type: StrategyType
  tokenPair: [Token, Token]
  apy: number
  tvl: number
  riskLevel: RiskLevel
  supportedChains: Chain[]
  feeTier: number
  createdAt: string
}

// Position types
export interface Position {
  id: string
  strategyId: string
  strategyName: string
  deployedAmount: number
  currentValue: number
  earnings: number
  apy: number
  chains: Chain[]
  createdAt: string
}

// Swap types
export interface SwapRoute {
  fromChain: Chain
  toChain: Chain
  hops: SwapHop[]
  estimatedTime: number
  totalFees: number
  priceImpact: number
}

export interface SwapHop {
  protocol: string
  chain: Chain
  tokenIn: Token
  tokenOut: Token
}

// Transaction types
export type TransactionType = 'swap' | 'deposit' | 'withdraw' | 'claim'
export type TransactionStatus = 'pending' | 'completed' | 'failed'

export interface Transaction {
  id: string
  type: TransactionType
  status: TransactionStatus
  amount: number
  token: Token
  chain: Chain
  timestamp: string
  hash: string
}

// User profile types
export interface UserStats {
  totalLiquidityDeployed: number
  totalEarnings: number
  activePositions: number
  averageApy: number
}

// Create strategy form types
export interface CreateStrategyForm {
  type: StrategyType
  tokenPair: [string, string]
  feeTier: number
  priceRange?: { min: number; max: number }
  chains: string[]
  initialLiquidity: number
}
