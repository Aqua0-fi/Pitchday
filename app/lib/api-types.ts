// GET /health
export interface HealthResponse {
  status: string
  timestamp: string
}

// GET /api/v1/chains
export interface ApiChain {
  id: number
  name: string
  displayName: string
}

export interface ChainsResponse {
  chains: ApiChain[]
}

// GET /api/v1/tokens
export interface ApiToken {
  id: string
  address: string
  chain: string
  symbol: string
  name: string
  decimals: number
  logoUrl: string | null
  isStablecoin: boolean
  isNativeWrapper: boolean
  priceUsd: number | null
  priceUpdatedAt: string | null
}

export interface TokensResponse {
  tokens: ApiToken[]
}

// GET /api/v1/strategies
export interface ApiStrategy {
  strategyHash: string
  app: string
  tokenIn: string
  tokenOut: string
  chainId: number
  feeBps: number
  isActive: boolean
  registeredAt: number
  displayName: string | null
  description: string | null
  strategyType: string | null
  riskLevel: string | null
  isFeatured: boolean
  apy24h: number | null
  apy7d: number | null
  tvlUsd: number | null
  volume24hUsd: number | null
  supportedChains: string[]
}

export interface StrategiesResponse {
  strategies: ApiStrategy[]
}

// GET /api/v1/strategies/:hash
export interface ApiStrategyDetail extends ApiStrategy {
  feeRecipient: string
  bytecode: string
  registeredAtBlock: number
  registeredAtTimestamp: number
  amplificationFactor: number | null
  apy30d: number | null
  stats: ApiStrategyStats | null
}

export interface StrategyDetailResponse {
  strategy: ApiStrategyDetail
}

// GET /api/v1/strategies/:hash/stats
export interface ApiStrategyStats {
  totalSwaps: number
  totalVolumeIn: string
  totalVolumeOut: string
  totalFees: string
  activeMakers: number
  totalVirtualBalance: string
  lastSwapTimestamp: number
}

export interface StrategyStatsResponse {
  stats: ApiStrategyStats | ApiStrategyStats[]
}

// GET /api/v1/positions/:wallet
export interface ApiPosition {
  id: string
  lpAccountAddress: string
  strategyHash: string
  chain: string
  ownerAddress: string
  tokenAddress: string
  app: string
  balanceRaw: string
  balanceUsd: number
  depositedUsd: number
  earnedFeesUsd: number
  pnlUsd: number
  pnlPercentage: number
  isActive: boolean
  lastSyncedAt: string
  createdAt: string
}

export interface PositionsResponse {
  positions: ApiPosition[]
  lpAccounts: unknown[]
}

// GET /api/v1/positions/:wallet/summary
export interface PositionSummaryResponse {
  summary: {
    totalLpAccounts: number
    totalValueUsd: number
    totalEarnedFeesUsd: number
    totalPnlUsd: number
    activeStrategies: number
    chains: string[]
  }
}

// GET /api/v1/positions/:wallet/history
export interface PositionHistoryResponse {
  events: unknown[]
}

// GET /api/v1/users/:wallet
export interface ApiUser {
  id: string
  walletAddress: string
  worldIdVerified: boolean
  createdAt: string
  lastSeenAt: string
}

// GET /api/v1/users/:wallet/preferences
export interface ApiUserPreferences {
  defaultSlippageBps: number
  preferredChains: string[]
  theme: string
  notificationsEnabled: boolean
  notificationEmail: string | null
}

// GET /api/v1/metrics
export interface MetricsResponse {
  current: {
    totalVtvlUsd: string
    totalVolumeUsd: string
    totalSwaps: number
    totalFeesUsd: string
    chain: string
    chainMetrics: unknown
  }
  history: unknown[]
}

// GET /api/v1/metrics/tvl
export interface TvlResponse {
  totalVtvlUsd: string
  topStrategies: unknown[]
}

// GET /api/v1/metrics/volume
export interface VolumeResponse {
  totalVolume24h: number
  totalVolume7d: number
  totalVolume30d: number
  history: unknown[]
}

// GET /api/v1/metrics/fees
export interface FeesResponse {
  totalProtocolFees24h: number
  totalLpFees24h: number
  totalProtocolFees30d: number
  totalLpFees30d: number
  history: unknown[]
}

// GET /api/v1/swaps/history/:wallet & /swaps/recent
export interface ApiSwap {
  id: string
  strategyHash: string
  tokenIn: string
  tokenOut: string
  amountIn: string
  amountOut: string
  takerAddress: string
  chainId: number
  timestamp: number
  txHash: string
}

export interface SwapsResponse {
  swaps: ApiSwap[]
}

// GET /api/v1/rebalancer/:wallet
export interface RebalancerConfigResponse {
  config: {
    id: string
    lpAccountAddress: string
    ownerAddress: string
    isEnabled: boolean
    rebalancerAddress: string
    minRebalanceAmountUsd: number
    maxSlippageBps: number
    preferredSourceChain: string
    minHoursBetweenRebalances: number
    lastRebalanceAt: string | null
  } | null
  message?: string
}

// GET /api/v1/rebalancer/:lpAccount/operations
export interface RebalancerOperationsResponse {
  operations: unknown[]
}

// GET /api/v1/rebalancer/:lpAccount/pending
export interface RebalancerPendingResponse {
  pendingOperations: unknown[]
}

// POST /api/v1/swaps/quote & /api/v1/swaps/prepare — request body
export interface SwapOrderRequest {
  order: {
    maker: string       // LP Account address (strategy.app)
    traits: string      // uint256 decimal string (includes USE_AQUA_BIT = 2^254)
    data: string        // "0x..." strategy bytecode hex
  }
  tokenIn: string       // "0x..." token address
  tokenOut: string      // "0x..." token address
  amountIn: string      // uint256 decimal string (smallest unit)
  takerData: string     // "0x..." threshold + flags
}

// POST /api/v1/swaps/quote — response
export interface SwapQuoteResponse {
  quote: {
    amountIn: string       // uint256 decimal string
    amountOut: string      // uint256 decimal string
    strategyHash: string   // "0x..." bytes32
  }
}

// POST /api/v1/swaps/prepare — response
export interface SwapPrepareResponse {
  calldata: {
    to: string    // SwapVMRouter address
    data: string  // encoded calldata hex
  }
}

// POST /api/v1/strategies/build — request body
export interface StrategyBuildRequest {
  template: 'constantProduct' | 'stableSwap'
  maker: string          // LP Account address
  token0: string         // token address
  token1: string         // token address
  balance0: string       // uint256 decimal string
  balance1: string       // uint256 decimal string
  feeBps: number         // fee in basis points (e.g. 30 = 0.3%)
  linearWidth?: string   // stableSwap only — A parameter scaled by 1e27
  rate0?: string         // stableSwap only — decimal normalization
  rate1?: string         // stableSwap only — decimal normalization
}

// POST /api/v1/strategies/build — response
export interface StrategyBuildResponse {
  program: string            // "0x..." SwapVM bytecode hex
  order: {
    maker: string            // LP Account address
    traits: string           // uint256 decimal string (includes USE_AQUA_BIT)
    data: string             // "0x..." program bytecode
  }
  strategyBytes: string      // "0x..." abi.encode(order)
  strategyHash: string       // "0x..." keccak256(strategyBytes)
  tokens: string[]           // token addresses
  amounts: string[]          // uint256 decimal strings
  takerData: string          // "0x..." threshold + flags
}

// POST /api/v1/lp/accounts/prepare-create — response
// POST /api/v1/lp/accounts/:address/prepare-approve — response
export interface PrepareCalldataResponse {
  calldata: {
    to: string    // contract address to call
    data: string  // encoded calldata hex
  }
}

// POST /api/v1/lp/accounts/:address/prepare-ship — response
export interface PrepareShipResponse {
  calldata: {
    to: string
    data: string
  }
  strategyHash: string   // "0x..." bytes32
}
