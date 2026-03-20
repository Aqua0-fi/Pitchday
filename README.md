# Aqua0 — Shared Liquidity for Uniswap V4

**One deposit. Multiple pools. Amplified yield.**

Aqua0 is a shared liquidity layer for Uniswap V4 that lets liquidity providers deposit capital once and have it simultaneously back multiple V4 pools through virtual positions and Just-In-Time (JIT) liquidity injection — without ever moving tokens between contracts.

> Deployed on **Unichain Sepolia** — all contracts are live and functional.

---

## The Problem

In traditional DeFi, liquidity is **fragmented**. If you want to earn fees on 3 different Uniswap V4 pools, you need to split your capital 3 ways — each pool only gets a fraction of your liquidity. This is capital-inefficient and limits yield.

## The Solution

Aqua0 introduces **Shared Liquidity Amplification** (SLAC):

1. **Deposit once** into the `SharedLiquidityPool` contract
2. **Amplify to N pools** — your same capital backs multiple V4 pools simultaneously via virtual positions
3. **Earn fees from all pools** — each swap across any connected pool generates fees for your single deposit
4. **No token movement** — amplification is purely virtual; your tokens never leave the SharedLiquidityPool

A $10,000 deposit amplified across 3 pools effectively provides $10,000 of liquidity to **each** pool — a 3x capital efficiency multiplier.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Uniswap V4 PoolManager            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐ │
│  │ Conserv. │  │Standard │  │Aggressive│  │ Tradi. │ │
│  │  Hook    │  │  Hook   │  │  Hook    │  │  Hook  │ │
│  └────┬─────┘  └────┬────┘  └────┬─────┘  └───┬────┘ │
│       │             │            │             │      │
│       └─────────────┼────────────┘             │      │
│                     │ (Aqua0BaseHook)          │      │
│                     ▼                     (isolated)  │
│          ┌──────────────────┐                         │
│          │SharedLiquidityPool│◄── User deposits here  │
│          │  (single vault)   │                        │
│          └──────────────────┘                         │
└──────────────────────────────────────────────────────┘
```

### Core Contracts

| Contract | Description |
|---|---|
| **`SharedLiquidityPool.sol`** | Central vault holding all LP deposits. Tracks per-user balances (`freeBalance`), virtual positions, and aggregated liquidity ranges. Authorized hooks and routers can read positions and settle swap deltas. |
| **`Aqua0BaseHook.sol`** | Abstract base contract that any V4 hook can inherit. Provides `_addVirtualLiquidity()` (beforeSwap) and `_removeVirtualLiquidityAndSettle()` (afterSwap) — the JIT mechanism that injects shared liquidity into swaps on-the-fly. |
| **`Aqua0Hook.sol`** | Default implementation of Aqua0BaseHook. A simple V4 hook with `beforeSwap` + `afterSwap` that demonstrates the JIT shared liquidity pattern. |
| **`Aqua0QuoteHelper.sol`** | On-chain helper for computing swap quotes without executing transactions. |

### Tranches (TrancheFi Integration)

| Contract | Description |
|---|---|
| **`TranchesHook.sol`** | V4 hook that extends Aqua0BaseHook with Senior/Junior tranche fee distribution. Senior tranche gets priority yield (target APY ~5%), Junior tranche gets the residual upside. |
| **`TranchesRouter.sol`** | Router for depositing/withdrawing liquidity into tranches. Supports both direct deposits and amplified deposits from the SharedLiquidityPool. |
| **`TrancheFiCallbackReceiver.sol`** | Callback receiver for Uniswap V4 unlock operations. |
| **`TrancheFiVolatilityRSC.sol`** | Volatility-based Revenue Sharing Contract that adjusts Senior/Junior splits based on market conditions. |

---

## How JIT Shared Liquidity Works

The magic happens in two V4 hook callbacks:

### `beforeSwap` — Inject Liquidity
```
1. SharedLiquidityPool returns all active virtual ranges for this pool
2. Hook calls poolManager.modifyLiquidity(+) for each range
3. Liquidity amounts are stored in transient storage
→ The pool now has deep liquidity for this swap
```

### `afterSwap` — Withdraw & Settle
```
1. Hook calls poolManager.modifyLiquidity(-) to remove the JIT liquidity
2. Net delta (fees earned) is computed: withdrawal - original deposit
3. Hook calls manager.take() to withdraw fee tokens from PoolManager
4. Fee tokens are transferred to SharedLiquidityPool
5. manager.settle() closes the accounting loop
→ Fees accrue to LPs, liquidity is "returned" (it was virtual)
```

The key insight: **tokens never actually move during amplification**. The SharedLiquidityPool holds them at all times. The V4 PoolManager's flash accounting allows the hook to add/remove liquidity within a single transaction, capturing fees without real token transfers.

---

## Pool Strategies

The demo includes 4 pool strategies with different risk profiles:

| Strategy | Tick Range | Fee Tier | Risk Profile |
|---|---|---|---|
| **Conservative** | ±100 ticks | 3000 (0.3%) | Narrow range, higher fees per swap, more IL risk |
| **Standard** | ±500 ticks | 3000 (0.3%) | Balanced range, moderate fees |
| **Aggressive** | ±1000 ticks | 10000 (1%) | Wide range, high fee tier, Senior/Junior tranches |
| **Traditional** | ±500 ticks | 3000 (0.3%) | Isolated pool (no shared liquidity) — the control group |

The **Traditional** pool serves as a baseline for comparison: same fee tier and range as Standard, but with isolated liquidity — demonstrating that Aqua0 shared pools earn more fees from the same capital.

---

## Frontend

The Next.js web app (`/app`) provides:

- **Dashboard** (`/dashboard`) — Deposit mUSDC/mWETH into the SharedLiquidityPool, view balances, and amplify capital to pools
- **Pools** (`/pools`) — Browse all V4 pools, view stats (TVL, fees earned, amplification multiplier)
- **Pool Detail** (`/pools/[id]`) — Deposit/withdraw from specific pools, view position details
- **Swap** (`/swap`) — Execute swaps against any pool via the V4 PoolSwapTest router
- **Strategy** (`/strategy`) — Compare Aqua0 amplified vs Traditional isolated performance

### Tech Stack
- Next.js 14 + TypeScript
- wagmi v2 + viem for wallet interactions
- Privy for authentication
- Tailwind CSS
- Unichain Sepolia (chainId: 1301)

---

## Deployed Addresses (Unichain Sepolia)

| Contract | Address |
|---|---|
| SharedLiquidityPool | `0x4AF9223D10fa40eacaBd6CfaC52dD78B6672778F` |
| Conservative Hook | `0x702E80d64aDa53cB66Bdc96Fa2F86Fd8e46a15C5` |
| Standard Hook | `0x2Ec2141371aa6bC8C5FdcB7A1A46F5180E5595C5` |
| Aggressive Hook | `0x1eB5129D6f36e2Ade3a53E6E2e83223318f295C5` |
| Traditional Hook (Isolated) | `0x7Ce487bB7dC0166E2B62caDA01E9130c6b9715C5` |
| IsolatedPool | `0x4c551cFBE3851832A517011d5A6555dBcadD8417` |
| PoolSwapTest | `0x3a89e21Ed936Bb2D6360fD4459C5ffeAA0053907` |
| mUSDC | `0x73c56ddD816e356387Caf740c804bb9D379BE47E` |
| mWETH | `0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad` |

---

## Getting Started

### Prerequisites
- [Foundry](https://book.getfoundry.sh/) for smart contract development
- Node.js 18+ for the frontend
- A wallet with Unichain Sepolia ETH

### Contracts
```bash
cd contracts
forge install
forge build
```

### Frontend
```bash
cd app
npm install
cp .env.local.example .env.local  # Add your Privy app ID
npm run dev                         # Runs on http://localhost:8080
```

### Deploy (Unichain Sepolia)
```bash
cd contracts

# Deploy everything fresh (hooks, SharedLiquidityPool, pools)
forge script script/UpgradeHooks.s.sol:UpgradeHooks \
  --rpc-url https://sepolia.unichain.org \
  --private-key $PRIVATE_KEY --broadcast -vvv

# Run demo swaps
bash script/run-demo-swaps.sh
```

---

## TrancheFi Integration

Aqua0 integrates with [TrancheFi](https://github.com/Aqua0-fi/TrancheFi) to demonstrate cross-protocol shared liquidity:

1. **Deposit** mUSDC/mWETH into Aqua0's SharedLiquidityPool
2. **Amplify** to TrancheFi's pool — same capital that backs Aqua0 pools also backs TrancheFi
3. **Choose a tranche** — Senior (stable yield, priority fees) or Junior (higher risk, residual upside)
4. **Earn fees** from swaps on TrancheFi, distributed according to tranche rules

The TrancheFi router is authorized in the SharedLiquidityPool, allowing it to create virtual positions against shared capital without requiring separate deposits.

---

## Key Concepts

### Virtual Positions
When a user "amplifies" their deposit to a pool, `addPosition()` checks that the user has sufficient `freeBalance` but does **not** lock or subtract tokens. The same capital can back N pools simultaneously — this is the core amplification mechanism.

### Flash Accounting
Uniswap V4's flash accounting model allows hooks to add/remove liquidity within a single transaction without pre-funding. Aqua0 exploits this: liquidity is injected in `beforeSwap` and removed in `afterSwap`, with only the net fee delta being settled.

### Authorized Routers
The SharedLiquidityPool maintains a mapping of `authorizedRouters` — external contracts (like TrancheFi's router) that can create/remove positions on behalf of users. This enables cross-protocol composability.

### CREATE2 Hook Mining
V4 hooks must have specific bits set in their address to indicate which callbacks they implement. Aqua0 uses CREATE2 with salt mining (via `HookMiner.sol`) to deploy hooks at addresses with the correct bit patterns.

---

## Repository Structure

```
pitch-demo/
├── app/                        # Next.js frontend
│   ├── app/                    # App router pages
│   │   ├── dashboard/          # Deposit & amplify
│   │   ├── pools/              # Pool list & details
│   │   ├── swap/               # Token swaps
│   │   └── strategy/           # Performance comparison
│   ├── hooks/                  # React hooks (wagmi, contracts)
│   ├── lib/                    # ABIs, contract config, V4 API
│   └── components/             # UI components
├── contracts/
│   ├── src/v4/                 # Core Solidity contracts
│   │   ├── SharedLiquidityPool.sol
│   │   ├── Aqua0BaseHook.sol
│   │   ├── Aqua0Hook.sol
│   │   ├── Aqua0QuoteHelper.sol
│   │   └── tranches/           # TrancheFi contracts
│   └── script/                 # Forge deploy scripts
└── README.md
```

---

## License

MIT

---

## Origin

This repository is a **fork of [contracts-hookathon](https://github.com/Aqua0-fi/contracts-hookathon)** — the original Uniswap V4 Hookathon submission. The `contracts/` directory was forked from the `tranches-own-pool` branch and the `app/` from the `tranches-frontend` branch, then extended with the SharedLiquidityPool architecture, JIT virtual liquidity, multi-pool amplification, and the TrancheFi integration for this pitch demo.

---

Built by the **Aqua0** team for the Uniswap V4 Hookathon.
