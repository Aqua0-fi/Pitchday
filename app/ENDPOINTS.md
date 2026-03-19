# Aqua0 API Endpoints — Integration Status

**Backend URL:** `https://api.aqua0.xyz`
**Auth:** Basic Auth + Header `X-API-Key`

---

## Legend

- 🟢 **Done** — Backend responds correctly + frontend hook created and tested
- 🟡 **In Progress** — Backend responds correctly, frontend hook pending
- 🔴 **To Do** — Not yet integrated (calldata builders, write endpoints)

---

## Health & Base

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 1 | `GET` | `/health` | 🟢 Done | `{"status":"ok"}` — hook: `useHealth()` |
| 2 | `GET` | `/ready` | 🟡 In Progress | Supabase ✅, Ponder ✅, Redis ❌ (not configured) |
| 3 | `GET` | `/api/v1/chains` | 🟢 Done | Hook: `useChains()` → mapped via `useMappedChains()` → `swap/page.tsx` (chain selector) |

## Tokens

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 4 | `GET` | `/api/v1/tokens` | 🟢 Done | Hook: `useTokens()` → mapped via `useMappedTokens()` → `swap/page.tsx` + `token-selector.tsx` |
| 5 | `GET` | `/api/v1/tokens?stablecoin=true` | 🟢 Done | Filters stablecoins — hook: `useStablecoins()` |
| 6 | `GET` | `/api/v1/tokens/:address` | 🟢 Done | Fixed case-sensitivity bug (`.eq` → `.ilike`). Works with checksum & lowercase |

## Strategies

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 7 | `GET` | `/api/v1/strategies` | 🟢 Done | Hook: `useStrategies()` → mapped via `useMappedStrategies()` → `app/page.tsx` |
| 8 | `GET` | `/api/v1/strategies/featured` | 🟢 Done | Hook: `useFeaturedStrategies()` → mapped via `useMappedFeaturedStrategies()` |
| 9 | `GET` | `/api/v1/strategies/:hash` | 🟢 Done | Hook: `useStrategy(hash)` → mapped via `useMappedStrategy()` → `strategy/[id]/page.tsx` |
| 10 | `GET` | `/api/v1/strategies/:hash/stats` | 🟢 Done | Hook: `useStrategyStats(hash)` → `strategy/[id]/page.tsx` |
| 11 | `POST` | `/api/v1/strategies/build` | 🟢 Done | Generates SwapVM bytecode. ⚠️ Opcodes off by +1 vs frontend |

## LP Accounts

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 12 | `POST` | `/api/v1/lp/accounts/prepare-create` | 🔴 To Do | Calldata builder — no DB needed |
| 13 | `GET` | `/api/v1/lp/accounts/:address` | 🟡 In Progress | Returns 500 — RPC call, may need valid LP account address |
| 14 | `GET` | `/api/v1/lp/accounts/:address/balance/:token` | 🟡 In Progress | Returns 500 — RPC call, needs valid LP account |
| 15 | `POST` | `/api/v1/lp/accounts/:address/prepare-approve` | 🔴 To Do | Calldata builder — no DB needed |
| 16 | `POST` | `/api/v1/lp/accounts/:address/prepare-ship` | 🔴 To Do | Calldata builder — no DB needed |
| 17 | `POST` | `/api/v1/lp/accounts/:address/prepare-dock` | 🔴 To Do | Calldata builder — no DB needed |
| 18 | `POST` | `/api/v1/lp/accounts/:address/prepare-withdraw` | 🔴 To Do | Calldata builder — no DB needed |
| 19 | `POST` | `/api/v1/lp/accounts/:address/prepare-withdraw-eth` | 🔴 To Do | Calldata builder — no DB needed |
| 20 | `POST` | `/api/v1/lp/accounts/:address/prepare-authorize-rebalancer` | 🔴 To Do | Calldata builder — no DB needed |
| 21 | `POST` | `/api/v1/lp/accounts/:address/prepare-revoke-rebalancer` | 🔴 To Do | Calldata builder — no DB needed |
| 22 | `POST` | `/api/v1/lp/accounts/:address/prepare-set-stargate-adapter` | 🔴 To Do | Calldata builder — no DB needed |
| 23 | `POST` | `/api/v1/lp/accounts/:address/prepare-set-composer` | 🔴 To Do | Calldata builder — no DB needed |
| 24 | `GET` | `/api/v1/lp/accounts/:address/strategies/:hash` | 🟡 In Progress | Returns 500 — RPC call, needs valid LP account |

## Positions

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 25 | `GET` | `/api/v1/positions/:wallet` | 🟢 Done | Hook: `usePositions(wallet)` → mapped via `useMappedPositions()` → `profile/page.tsx` |
| 26 | `GET` | `/api/v1/positions/:wallet/summary` | 🟢 Done | Hook: `usePositionSummary(wallet)` → mapped via `useMappedUserStats()` → `profile/page.tsx` |
| 27 | `GET` | `/api/v1/positions/:wallet/history` | 🟢 Done | Hook: `usePositionHistory(wallet)` |

## Swaps

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 28 | `POST` | `/api/v1/swaps/quote` | 🔴 To Do | RPC call to SwapVMRouter — no DB needed |
| 29 | `POST` | `/api/v1/swaps/prepare` | 🔴 To Do | Calldata builder — no DB needed |
| 30 | `GET` | `/api/v1/swaps/history/:wallet` | 🟢 Done | Hook: `useSwapHistory(wallet)` → mapped via `useMappedTransactions()` → `profile/page.tsx` |
| 31 | `GET` | `/api/v1/swaps/recent` | 🟢 Done | Hook: `useRecentSwaps()` |
| 32 | `GET` | `/api/v1/swaps/:id` | 🟡 In Progress | Needs real swap ID to test |
| 33 | `GET` | `/api/v1/swaps/by-strategy/:hash` | 🟡 In Progress | Needs real strategy hash to test |

## Metrics

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 34 | `GET` | `/api/v1/metrics` | 🟢 Done | Hook: `useMetrics()` |
| 35 | `GET` | `/api/v1/metrics/tvl` | 🟢 Done | Hook: `useTvl()` → `app/page.tsx` (Total Value Locked stat) |
| 36 | `GET` | `/api/v1/metrics/volume` | 🟢 Done | Hook: `useVolume()` → `app/page.tsx` (Volume 24h stat) |
| 37 | `GET` | `/api/v1/metrics/fees` | 🟢 Done | Hook: `useFees()` → `app/page.tsx` (Fees 24h stat) |

## Users

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 38 | `GET` | `/api/v1/users/:wallet` | 🟢 Done | Hook: `useUser(wallet)` → `profile/page.tsx` (member since date) — 404 for unknown wallets is correct |
| 39 | `POST` | `/api/v1/users` | 🔴 To Do | Creates user — write endpoint, deferred |
| 40 | `GET` | `/api/v1/users/:wallet/preferences` | 🟢 Done | Hook: `useUserPreferences(wallet)` — 404 for unknown is correct |
| 41 | `PUT` | `/api/v1/users/:wallet/preferences` | 🔴 To Do | Updates preferences — write endpoint, deferred |

## Rebalancer

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 42 | `GET` | `/api/v1/rebalancer/:wallet` | 🟢 Done | Hook: `useRebalancerConfig(wallet)` |
| 43 | `PUT` | `/api/v1/rebalancer/:lpAccount` | 🔴 To Do | Updates config — write endpoint, deferred |
| 44 | `GET` | `/api/v1/rebalancer/:lpAccount/operations` | 🟢 Done | Hook: `useRebalancerOperations(lpAccount)` |
| 45 | `GET` | `/api/v1/rebalancer/:lpAccount/pending` | 🟢 Done | Hook: `usePendingRebalances(lpAccount)` |
| 46 | `POST` | `/api/v1/rebalancer/operations/prepare-trigger` | 🔴 To Do | Calldata builder — no DB needed |
| 47 | `POST` | `/api/v1/rebalancer/operations/:id/prepare-dock` | 🔴 To Do | Calldata builder — no DB needed |
| 48 | `POST` | `/api/v1/rebalancer/operations/:id/prepare-bridge` | 🔴 To Do | Calldata builder — no DB needed |
| 49 | `POST` | `/api/v1/rebalancer/operations/:id/prepare-record-bridging` | 🔴 To Do | Calldata builder — no DB needed |
| 50 | `POST` | `/api/v1/rebalancer/operations/:id/prepare-confirm` | 🔴 To Do | Calldata builder — no DB needed |
| 51 | `POST` | `/api/v1/rebalancer/operations/:id/prepare-fail` | 🔴 To Do | Calldata builder — no DB needed |
| 52 | `GET` | `/api/v1/rebalancer/operations/:id` | 🟡 In Progress | Returns 500 — needs valid operation ID |
| 53 | `POST` | `/api/v1/rebalancer/bridge/quote-fee` | 🔴 To Do | RPC call — no DB needed |
| 54 | `POST` | `/api/v1/rebalancer/bridge/quote-compose-fee` | 🔴 To Do | RPC call — no DB needed |

## Admin

| # | Method | Endpoint | Status | Notes |
|---|--------|----------|--------|-------|
| 55 | `GET` | `/api/v1/admin/strategies` | 🟡 In Progress | Returns strategy list from `strategy_metadata` — works |
| 56 | `POST` | `/api/v1/admin/strategies` | 🔴 To Do | Creates strategy metadata — needs testing |
| 57 | `PUT` | `/api/v1/admin/strategies/:hash` | 🔴 To Do | Updates strategy metadata — needs testing |
| 58 | `DELETE` | `/api/v1/admin/strategies/:hash` | 🔴 To Do | Deletes strategy metadata — needs testing |

---

## Summary

| Status | Count |
|--------|-------|
| 🟢 Done | 24 |
| 🟡 In Progress | 8 |
| 🔴 To Do | 26 |

## Remaining Blockers

| Issue | Details | Who |
|-------|---------|-----|
| **Redis not configured** | `/ready` shows Redis unhealthy. Need Redis service in Railway or skip (only caching). | Backend |
| **SwapVM opcodes mismatch** | Frontend opcodes (DynamicBalances=0x12, FlatFee=0x26, XYCSwap=0x16) are off by +1 vs backend (0x13, 0x27, 0x17). Need to confirm correct values. | Backend |
| **Testnet chains missing** | Backend only returns Base (8453) + Unichain (130). Need Base Sepolia (84532) + Unichain Sepolia (1301) for testnet dev. | Backend |
| **Token prices null** | All tokens have `priceUsd: null`. Need price feed integration (Coingecko, etc). | Backend |
| **LP Account RPC errors** | `GET /lp/accounts/:address` and `/balance/:token` return 500 — likely needs valid on-chain LP account address. | Frontend |
| **AccountFactory not deployed** | Smart contracts not deployed yet. LP Account create flow (`prepare-create`) blocked until CTO deploys contracts and provides factory address. | Backend/CTO |
