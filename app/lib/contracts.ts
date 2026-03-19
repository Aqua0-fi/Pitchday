import type { Address } from 'viem'

// SwapVMRouter / V4 PoolSwapTest Router
export const SWAP_VM_ROUTER: Address = '0x84175aA7EfD2805Ff8Dc2CF49EC3990b50daf3a1'

// USE_AQUA_BIT flag (1 << 254) — required in order.traits for the router
// Pre-computed: (1n << 254n).toString()
export const USE_AQUA_BIT = '28948022309329048855892746252171976963317496166410141009864396001978282409984'

// Backend chain ID mapping (matches API query param expectations)
export const BACKEND_CHAIN_IDS: Record<string | number, number> = {
  base: 8453,
  unichain: 1301,
  'unichain-sepolia': 1301,
  local: 696969,
  84532: 84532,
  1301: 1301,
  696969: 696969,
}

/**
 * Build takerData for swap orders.
 * Replicates backend's buildAquaTakerData():
 *   encodePacked(["uint160", "uint16"], [threshold, 0x0041])
 * Result: 22 bytes (20 for threshold + 2 for flags)
 */
export function buildTakerData(threshold: bigint = BigInt(0)): `0x${string}` {
  const thresholdHex = threshold.toString(16).padStart(40, '0')
  const flagsHex = '0041'
  return `0x${thresholdHex}${flagsHex}`
}

// Minimal ERC20 ABI for approve + allowance + transfer
export const ERC20_ABI = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ type: 'bool' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  {
    name: 'transfer',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ type: 'bool' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
] as const

// LP Account Factory — same address on all supported chains (deployed via CreateX)
export const ACCOUNT_FACTORY: Address = '0xfA4FCDF96866bD1ACCB6e70Aa426644E953E76b0'

// Minimal AccountFactory ABI for checking/creating LP Accounts
export const ACCOUNT_FACTORY_ABI = [
  {
    name: 'getAccount',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'salt', type: 'bytes32' },
    ],
    outputs: [{ type: 'address' }],
  },
  {
    name: 'isAccount',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'bool' }],
  },
] as const

// ─── Uniswap V4 PoolManager (Unichain Sepolia) ──────────────────────────────
export const POOL_MANAGER: Address = '0x00B036B58a818B1BC34d502D3fE730Db729e62AC'

// ─── TrancheFi Multi-Pool (Unichain Sepolia) ─────────────────────────────────

export const TRANCHES_SHARED_POOL: Address = '0xFe57Bb0319938BCA85d804a7ec7129EB6cB8Ea30'

// 4 TranchesHook pools — 3 Aqua (shared) + 1 Traditional (isolated)
export const TRANCHES_POOLS = [
  {
    label: 'Conservative',
    fee: 500,
    tickSpacing: 10,
    hook: '0x16326eCA33f5B28e3D572Ed38B066919E8E555C5' as Address,
    router: '0x019D1492Ec7fCbe96FD1F67f29eF17fAe3D23aDA' as Address,
    aqua: true,
  },
  {
    label: 'Standard',
    fee: 3000,
    tickSpacing: 60,
    hook: '0x8E104beAC6dA7351B00b36E9f2B248F2BfD595c5' as Address,
    router: '0xd21440fDAF823c666bAD74e607DCEA85944a3468' as Address,
    aqua: true,
  },
  {
    label: 'Aggressive',
    fee: 10000,
    tickSpacing: 200,
    hook: '0xA6a0b93092aF21cBAB5f69C243f0dA2cF466D5c5' as Address,
    router: '0x3D4Ec88C692F626d9D885d60E4Fe38A99403252F' as Address,
    aqua: true,
  },
  {
    label: 'Traditional',
    fee: 3000,
    tickSpacing: 60,
    hook: '0xAf99B4dBAeEfAeC6AbCb1018290ea705B3C895c5' as Address,
    router: '0x1f1dA6CbDD85FC06A14F7fD48e7563b612f1812c' as Address,
    aqua: false,
    isolatedPool: '0x88Db58098a952241432306dcdB0A33A3221e6D13' as Address,
  },
] as const

// Default to Standard pool for backwards compat
export const TRANCHES_HOOK: Address = TRANCHES_POOLS[1].hook
export const TRANCHES_ROUTER: Address = TRANCHES_POOLS[1].router

// Helper: check if a hook address is any of our TranchesHook pools
const TRANCHES_HOOK_SET = new Set(TRANCHES_POOLS.map(p => p.hook.toLowerCase()))
export function isTranchesHook(hookAddress: string): boolean {
  return TRANCHES_HOOK_SET.has(hookAddress.toLowerCase())
}

const TRADITIONAL_HOOK = TRANCHES_POOLS.find(p => !p.aqua)?.hook.toLowerCase()
export function isTraditionalHook(hookAddress: string): boolean {
  return hookAddress.toLowerCase() === TRADITIONAL_HOOK
}

// Global Aqua0 mock token addresses (Unichain Sepolia)
// currency0 must be the lower address per Uniswap V4 convention
export const TRANCHES_POOL_KEY = {
  currency0: '0x73c56ddD816e356387Caf740c804bb9D379BE47E' as Address, // mUSDC
  currency1: '0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad' as Address, // mWETH
  fee: 3000,
  tickSpacing: 60,
  hooks: TRANCHES_POOLS[1].hook,
} as const

const POOL_KEY_TUPLE = {
  type: 'tuple' as const,
  components: [
    { name: 'currency0', type: 'address' as const },
    { name: 'currency1', type: 'address' as const },
    { name: 'fee', type: 'uint24' as const },
    { name: 'tickSpacing', type: 'int24' as const },
    { name: 'hooks', type: 'address' as const },
  ],
}

export const TRANCHES_HOOK_ABI = [
  {
    name: 'getPoolStats',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'key', ...POOL_KEY_TUPLE }],
    outputs: [
      { name: 'totalSenior', type: 'uint256' },
      { name: 'totalJunior', type: 'uint256' },
      { name: 'seniorFees', type: 'uint256' },
      { name: 'juniorFees', type: 'uint256' },
      { name: 'seniorAPY', type: 'uint256' },
      { name: 'seniorRatio', type: 'uint256' },
    ],
  },
  {
    name: 'pendingFees',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'lp', type: 'address' },
      { name: 'key', ...POOL_KEY_TUPLE },
    ],
    outputs: [
      { name: 'pending0', type: 'uint256' },
      { name: 'pending1', type: 'uint256' },
    ],
  },
  {
    name: 'claimableBalance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: '', type: 'address' },
      { name: '', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'positions',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: '', type: 'bytes32' }],
    outputs: [
      { name: 'tranche', type: 'uint8' },
      { name: 'amount', type: 'uint256' },
      { name: 'depositBlock', type: 'uint256' },
      { name: 'rewardDebt0', type: 'uint256' },
      { name: 'rewardDebt1', type: 'uint256' },
      { name: 'depositSqrtPriceX96', type: 'uint160' },
    ],
  },
  {
    name: 'claimFees',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'key', ...POOL_KEY_TUPLE }],
    outputs: [],
  },
  {
    name: 'withdrawFees',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'currency', type: 'address' }],
    outputs: [],
  },
] as const

export const TRANCHES_ROUTER_ABI = [
  {
    name: 'addLiquidity',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'key', ...POOL_KEY_TUPLE },
      { name: 'tickLower', type: 'int24' },
      { name: 'tickUpper', type: 'int24' },
      { name: 'liquidity', type: 'uint128' },
      { name: 'amount0', type: 'uint256' },
      { name: 'amount1', type: 'uint256' },
      { name: 'tranche', type: 'uint8' },
    ],
    outputs: [],
  },
  {
    name: 'addLiquidityFromSharedPool',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'key', ...POOL_KEY_TUPLE },
      { name: 'tickLower', type: 'int24' },
      { name: 'tickUpper', type: 'int24' },
      { name: 'liquidity', type: 'uint128' },
      { name: 'amount0', type: 'uint256' },
      { name: 'amount1', type: 'uint256' },
      { name: 'tranche', type: 'uint8' },
    ],
    outputs: [],
  },
  {
    name: 'removeLiquidity',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'key', ...POOL_KEY_TUPLE },
      { name: 'tickLower', type: 'int24' },
      { name: 'tickUpper', type: 'int24' },
      { name: 'amount0Initial', type: 'uint256' },
      { name: 'amount1Initial', type: 'uint256' },
    ],
    outputs: [],
  },
] as const

// ─── V4 Router ────────────────────────────────────────────────────────────────

export const V4_ROUTER_ABI = [
  {
    "type": "function",
    "name": "swap",
    "inputs": [
      {
        "name": "key",
        "type": "tuple",
        "components": [
          { "name": "currency0", "type": "address" },
          { "name": "currency1", "type": "address" },
          { "name": "fee", "type": "uint24" },
          { "name": "tickSpacing", "type": "int24" },
          { "name": "hooks", "type": "address" }
        ]
      },
      {
        "name": "params",
        "type": "tuple",
        "components": [
          { "name": "zeroForOne", "type": "bool" },
          { "name": "amountSpecified", "type": "int256" },
          { "name": "sqrtPriceLimitX96", "type": "uint160" }
        ]
      },
      {
        "name": "testSettings",
        "type": "tuple",
        "components": [
          { "name": "takeClaims", "type": "bool" },
          { "name": "settleUsingBurn", "type": "bool" }
        ]
      },
      { "name": "hookData", "type": "bytes" }
    ],
    "outputs": [{ "name": "delta", "type": "int256" }],
    "stateMutability": "payable"
  }
] as const
