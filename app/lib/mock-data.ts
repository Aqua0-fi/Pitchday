import type { Chain, Token, Strategy, Position, Transaction, UserStats } from './types'

export const chains: Chain[] = [
  { id: 'base', name: 'Base', logo: '/crypto/Base.png', color: '#0052FF' },
  { id: 'unichain', name: 'Unichain', logo: '/crypto/Unichain.png', color: '#FF007A' },
]

export const tokens: Token[] = [
  { symbol: 'ETH', name: 'Ethereum', logo: '/crypto/ETH.png', decimals: 18, address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2' },
  { symbol: 'USDC', name: 'USD Coin', logo: '/crypto/USDC.png', decimals: 6, address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' },
  { symbol: 'USDT', name: 'Tether', logo: '/crypto/USDT.png', decimals: 6, address: '0xdAC17F958D2ee523a2206206994597C13D831ec7' },
  { symbol: 'WBTC', name: 'Wrapped Bitcoin', logo: '/crypto/BTC.png', decimals: 8, address: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599' },
  { symbol: 'wSOL', name: 'Wrapped Solana', logo: '/crypto/Solana.png', decimals: 9, address: '0xD31a59c85aE9D8edEFec411186ADc22f858aA5d0' },
  { symbol: 'DAI', name: 'Dai', logo: '/crypto/DAI.png', decimals: 18, address: '0x6B175474E89094C44Da98b954EedeAC495271d0F' },
]

export const strategies: Strategy[] = [
  {
    id: '1',
    name: 'ETH/USDC',
    type: 'constant-product',
    tokenPair: [tokens[0], tokens[1]],
    apy: 5.8,
    tvl: 12500000,
    riskLevel: 'medium',
    supportedChains: [chains[0]],
    feeTier: 0.3,
    createdAt: '2025-01-15',
  },
  {
    id: '2',
    name: 'USDC/USDT',
    type: 'stable-swap',
    tokenPair: [tokens[1], tokens[2]],
    apy: 3.2,
    tvl: 45000000,
    riskLevel: 'low',
    supportedChains: [chains[1]],
    feeTier: 0.01,
    createdAt: '2025-01-10',
  },
  {
    id: '3',
    name: 'WBTC/ETH',
    type: 'constant-product',
    tokenPair: [tokens[3], tokens[0]],
    apy: 4.5,
    tvl: 8200000,
    riskLevel: 'medium',
    supportedChains: [chains[1]],
    feeTier: 0.3,
    createdAt: '2025-01-08',
  },
]

export const positions: Position[] = [
  {
    id: '1',
    strategyId: '1',
    strategyName: 'ETH/USDC',
    deployedAmount: 50000,
    currentValue: 50725,
    earnings: 725,
    apy: 5.8,
    chains: [chains[0]],
    createdAt: '2025-01-15',
  },
  {
    id: '2',
    strategyId: '2',
    strategyName: 'USDC/USDT',
    deployedAmount: 100000,
    currentValue: 100400,
    earnings: 400,
    apy: 3.2,
    chains: [chains[1]],
    createdAt: '2025-01-10',
  },
  {
    id: '3',
    strategyId: '3',
    strategyName: 'WBTC/ETH',
    deployedAmount: 25000,
    currentValue: 25280,
    earnings: 280,
    apy: 4.5,
    chains: [chains[1]],
    createdAt: '2025-01-05',
  },
]

export const transactions: Transaction[] = [
  {
    id: '1',
    type: 'deposit',
    status: 'completed',
    amount: 50000,
    token: tokens[1],
    chain: chains[0],
    timestamp: '2025-01-20T14:30:00Z',
    hash: '0x1234...5678',
  },
  {
    id: '2',
    type: 'swap',
    status: 'completed',
    amount: 2.5,
    token: tokens[0],
    chain: chains[1],
    timestamp: '2025-01-19T10:15:00Z',
    hash: '0xabcd...efgh',
  },
  {
    id: '3',
    type: 'claim',
    status: 'completed',
    amount: 450,
    token: tokens[1],
    chain: chains[0],
    timestamp: '2025-01-18T16:45:00Z',
    hash: '0x9876...5432',
  },
  {
    id: '4',
    type: 'withdraw',
    status: 'pending',
    amount: 10000,
    token: tokens[1],
    chain: chains[1],
    timestamp: '2025-01-21T09:00:00Z',
    hash: '0xfedc...ba98',
  },
]

export const userStats: UserStats = {
  totalLiquidityDeployed: 175000,
  totalEarnings: 1405,
  activePositions: 3,
  averageApy: 4.5,
}

// Chart data
export const earningsOverTime = [
  { date: 'Jan 1', earnings: 0 },
  { date: 'Jan 5', earnings: 450 },
  { date: 'Jan 10', earnings: 1200 },
  { date: 'Jan 15', earnings: 2100 },
  { date: 'Jan 20', earnings: 3500 },
  { date: 'Jan 22', earnings: 4800 },
]

export const liquidityByChain = [
  { chain: 'Base', value: 147000, color: '#0052FF' },
  { chain: 'Unichain', value: 28000, color: '#FF007A' },
]

export const apyComparison = [
  { strategy: 'ETH/USDC', apy: 5.8 },
  { strategy: 'USDC/USDT', apy: 3.2 },
  { strategy: 'WBTC/ETH', apy: 4.5 },
]

// Strategy detail data
export const strategyDetailData = {
  '1': {
    volume24h: 2450000,
    volume7d: 18500000,
    fees24h: 7350,
    fees7d: 55500,
    fees30d: 245000,
    totalFeesCollected: 1250000,
    poolComposition: { tokenA: 52, tokenB: 48 },
    tokenAAmount: 6500,
    tokenBAmount: 13000000,
    currentPrice: 2000,
    apyHistory: [
      { date: 'Jan 1', apy: 5.2 },
      { date: 'Jan 5', apy: 5.5 },
      { date: 'Jan 10', apy: 6.1 },
      { date: 'Jan 15', apy: 5.7 },
      { date: 'Jan 20', apy: 5.9 },
      { date: 'Jan 22', apy: 5.8 },
    ],
    tvlHistory: [
      { date: 'Jan 1', tvl: 10500000 },
      { date: 'Jan 5', tvl: 11200000 },
      { date: 'Jan 10', tvl: 11800000 },
      { date: 'Jan 15', tvl: 12100000 },
      { date: 'Jan 20', tvl: 12350000 },
      { date: 'Jan 22', tvl: 12500000 },
    ],
    volumeHistory: [
      { date: 'Jan 1', volume: 1800000 },
      { date: 'Jan 5', volume: 2100000 },
      { date: 'Jan 10', volume: 2600000 },
      { date: 'Jan 15', volume: 2200000 },
      { date: 'Jan 20', volume: 2450000 },
      { date: 'Jan 22', volume: 2450000 },
    ],
    recentActivity: [
      { id: '1', type: 'swap', amount: '2.5 ETH', price: '$5,000', time: '2 min ago', hash: '0x1234...5678' },
      { id: '2', type: 'add', amount: '10,000 USDC', price: '-', time: '15 min ago', hash: '0xabcd...efgh' },
      { id: '3', type: 'swap', amount: '1.2 ETH', price: '$2,400', time: '23 min ago', hash: '0x9876...5432' },
      { id: '4', type: 'remove', amount: '5,000 USDC', price: '-', time: '1 hour ago', hash: '0xfedc...ba98' },
      { id: '5', type: 'swap', amount: '0.8 ETH', price: '$1,600', time: '2 hours ago', hash: '0x5555...6666' },
    ],
    userPosition: {
      hasPosition: true,
      value: 52450,
      earnings: 2450,
      share: 0.42,
    },
  },
  '2': {
    volume24h: 8500000,
    volume7d: 62000000,
    fees24h: 850,
    fees7d: 6200,
    fees30d: 28000,
    totalFeesCollected: 450000,
    poolComposition: { tokenA: 50.2, tokenB: 49.8 },
    tokenAAmount: 22500000,
    tokenBAmount: 22400000,
    currentPrice: 1.001,
    apyHistory: [
      { date: 'Jan 1', apy: 3.0 },
      { date: 'Jan 5', apy: 3.1 },
      { date: 'Jan 10', apy: 3.3 },
      { date: 'Jan 15', apy: 3.1 },
      { date: 'Jan 20', apy: 3.2 },
      { date: 'Jan 22', apy: 3.2 },
    ],
    tvlHistory: [
      { date: 'Jan 1', tvl: 42000000 },
      { date: 'Jan 5', tvl: 43000000 },
      { date: 'Jan 10', tvl: 44000000 },
      { date: 'Jan 15', tvl: 44500000 },
      { date: 'Jan 20', tvl: 45000000 },
      { date: 'Jan 22', tvl: 45000000 },
    ],
    volumeHistory: [
      { date: 'Jan 1', volume: 7500000 },
      { date: 'Jan 5', volume: 8000000 },
      { date: 'Jan 10', volume: 9200000 },
      { date: 'Jan 15', volume: 8100000 },
      { date: 'Jan 20', volume: 8500000 },
      { date: 'Jan 22', volume: 8500000 },
    ],
    recentActivity: [
      { id: '1', type: 'swap', amount: '50,000 USDC', price: '$50,050', time: '1 min ago', hash: '0xaaaa...bbbb' },
      { id: '2', type: 'swap', amount: '25,000 USDT', price: '$24,975', time: '5 min ago', hash: '0xcccc...dddd' },
      { id: '3', type: 'add', amount: '100,000 USDC', price: '-', time: '30 min ago', hash: '0xeeee...ffff' },
      { id: '4', type: 'swap', amount: '75,000 USDC', price: '$75,075', time: '45 min ago', hash: '0x1111...2222' },
      { id: '5', type: 'remove', amount: '20,000 USDT', price: '-', time: '1 hour ago', hash: '0x3333...4444' },
    ],
    userPosition: {
      hasPosition: true,
      value: 101200,
      earnings: 1200,
      share: 0.22,
    },
  },
  '3': {
    volume24h: 1200000,
    volume7d: 9500000,
    fees24h: 3600,
    fees7d: 28500,
    fees30d: 125000,
    totalFeesCollected: 680000,
    poolComposition: { tokenA: 48, tokenB: 52 },
    tokenAAmount: 195,
    tokenBAmount: 4100,
    currentPrice: 21.03,
    apyHistory: [
      { date: 'Jan 1', apy: 4.2 },
      { date: 'Jan 5', apy: 4.4 },
      { date: 'Jan 10', apy: 4.7 },
      { date: 'Jan 15', apy: 4.5 },
      { date: 'Jan 20', apy: 4.5 },
      { date: 'Jan 22', apy: 4.5 },
    ],
    tvlHistory: [
      { date: 'Jan 1', tvl: 7500000 },
      { date: 'Jan 5', tvl: 7800000 },
      { date: 'Jan 10', tvl: 8000000 },
      { date: 'Jan 15', tvl: 8100000 },
      { date: 'Jan 20', tvl: 8200000 },
      { date: 'Jan 22', tvl: 8200000 },
    ],
    volumeHistory: [
      { date: 'Jan 1', volume: 1000000 },
      { date: 'Jan 5', volume: 1100000 },
      { date: 'Jan 10', volume: 1350000 },
      { date: 'Jan 15', volume: 1200000 },
      { date: 'Jan 20', volume: 1200000 },
      { date: 'Jan 22', volume: 1200000 },
    ],
    recentActivity: [
      { id: '1', type: 'swap', amount: '0.5 WBTC', price: '$21,000', time: '5 min ago', hash: '0x7777...8888' },
      { id: '2', type: 'add', amount: '2 WBTC', price: '-', time: '20 min ago', hash: '0x9999...0000' },
      { id: '3', type: 'swap', amount: '5 ETH', price: '$10,500', time: '35 min ago', hash: '0xaaaa...1111' },
      { id: '4', type: 'swap', amount: '0.3 WBTC', price: '$12,600', time: '1 hour ago', hash: '0xbbbb...2222' },
      { id: '5', type: 'remove', amount: '1 WBTC', price: '-', time: '2 hours ago', hash: '0xcccc...3333' },
    ],
    userPosition: {
      hasPosition: false,
      value: 0,
      earnings: 0,
      share: 0,
    },
  },
}

// User token balances (mock)
export const userBalances: Record<string, number> = {
  ETH: 5.25,
  USDC: 12500,
  USDT: 8000,
  WBTC: 0.15,
  wSOL: 25.0,
  DAI: 3500,
}
