# TrancheFi x Aqua0 — Deployment & Integration Reference

## Deployed Contracts (Unichain Sepolia — Chain 1301)

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| **TranchesHook**     | `0x45Cd925cC9fc27E34462CD769D46E8e5274Bd5c5` |
| **TranchesRouter**   | `0x6AE54EBfECb6E1eb159bFDdB4CE40408B77da524` |
| **SharedLiquidityPool** | `0xF7a4797f0b034F8e666c39F1c001d49e79331165` |
| **tWETH (currency0)**   | `0x18E2b73Bfd9F9624906a4dB7f8AcBd4524D09d94` |
| **tUSDC (currency1)**   | `0xd858030873521Aefb8B3f0D4931f27fe12E87440` |
| PoolManager (Uniswap) | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| Deployer              | `0x5ba6C6F599C74476d335B7Ad34C97F9c842e8734` |

**Block:** 46488521
**Hook salt:** `0x1735` (5941)
**Hook flags:** `0x15C5` (afterInit | afterAddLiq | afterRemoveLiq | beforeSwap | afterSwap | afterSwapRetDelta | afterRemoveLiqRetDelta)

## Pool Configuration

| Parameter      | Value                              |
| -------------- | ---------------------------------- |
| Fee            | 3000 (0.30%)                       |
| Tick spacing   | 60                                 |
| Initial price  | 1:1 (sqrtPriceX96 = 79228162514264337593543950336) |
| Seed liquidity | 100e18 (full range -887220 to 887220) |

## PoolKey (for frontend / contract calls)

```
currency0:   0x18E2b73Bfd9F9624906a4dB7f8AcBd4524D09d94  (tWETH)
currency1:   0xd858030873521Aefb8B3f0D4931f27fe12E87440  (tUSDC)
fee:         3000
tickSpacing: 60
hooks:       0x45Cd925cC9fc27E34462CD769D46E8e5274Bd5c5  (TranchesHook)
```

## Architecture

```
                    ┌─────────────────────┐
                    │   TranchesRouter    │  Atomic deposits/removals
                    │   (0x6AE5...)       │  (prevents hookData spoofing)
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │   TranchesHook      │  Senior/Junior tranches
                    │   (0x45Cd...)       │  Waterfall fee distribution
                    │                     │  IL protection for Senior
                    │   inherits:         │
                    │   Aqua0BaseHook     │  JIT shared liquidity
                    └─────────┬───────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
    ┌─────────▼─────┐  ┌─────▼─────┐  ┌──────▼──────────┐
    │ PoolManager   │  │ SharedLP  │  │ CallbackReceiver │
    │ (Uniswap V4)  │  │ (0xF7a4)  │  │ (Reactive Net)   │
    └───────────────┘  └───────────┘  └─────────────────┘
```

## How It Works

**Tranches:**
- **Senior** — Priority fees, IL protection, lower risk, target APY (default 5%)
- **Junior** — Residual fees after Senior is paid, higher risk/reward

**Swap flow (with Aqua0 JIT):**
1. `beforeSwap` → Aqua0BaseHook injects virtual liquidity from SharedLiquidityPool
2. Swap executes against pool + JIT liquidity
3. `afterSwap` → Removes JIT liquidity, settles deltas with SharedPool
4. `afterSwap` → TranchesHook distributes fees via waterfall: Senior first (up to target APY), Junior gets remainder

**Fee claim (2-step pull):**
1. `hook.claimFees(poolKey)` → moves pending fees to claimable balance
2. `hook.withdrawFees(currency)` → transfers tokens to wallet

## Key Contract Functions

### TranchesRouter (user-facing)
```solidity
// Deposit into a tranche (Senior or Junior)
addLiquidity(PoolKey key, ModifyLiquidityParams params, TranchesHook.Tranche tranche)

// Remove liquidity
removeLiquidity(PoolKey key, ModifyLiquidityParams params)
```

### TranchesHook (read functions)
```solidity
// Pool stats: (seniorLiq, juniorLiq, seniorFees, juniorFees, targetAPY, seniorRatio)
getPoolStats(PoolKey key) → (uint256, uint256, uint256, uint256, uint256, uint256)

// Pending fees for an LP
pendingFees(address lp, PoolKey key) → (uint256 fee0, uint256 fee1)

// Claimable balance (after claimFees)
claimableBalance(address lp, Currency currency) → uint256

// Claim fees (move pending → claimable)
claimFees(PoolKey key)

// Withdraw (transfer claimable to wallet)
withdrawFees(Currency currency)

// Admin: set risk parameter (called by RSC or authorized)
adjustRiskParameter(PoolKey key, uint256 newSeniorTargetAPY)
```

## Commands

### Run tests
```bash
forge test --match-path test/TranchesHookIntegration.t.sol -vvv
```

### Redeploy (if needed)
```bash
source .env && forge script script/DeployTranches.s.sol:DeployTranches \
  --rpc-url https://sepolia.unichain.org \
  --broadcast -vvv
```

### Verify on explorer
```bash
source .env && forge verify-contract \
  0x45Cd925cC9fc27E34462CD769D46E8e5274Bd5c5 \
  src/v4/tranches/TranchesHook.sol:TranchesHook \
  --chain 1301 \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" \
    0x00B036B58a818B1BC34d502D3fE730Db729e62AC \
    0xF7a4797f0b034F8e666c39F1c001d49e79331165 \
    0x5ba6C6F599C74476d335B7Ad34C97F9c842e8734)
```

## File Structure

```
src/v4/tranches/
├── TranchesHook.sol              # Main hook (Senior/Junior + Aqua0 JIT)
├── TranchesRouter.sol            # Atomic deposit/removal router
├── TrancheFiCallbackReceiver.sol # Reactive Network → hook bridge
└── TrancheFiVolatilityRSC.sol    # Cross-chain volatility monitor (RSC)

script/
└── DeployTranches.s.sol          # Full deployment script

test/
└── TranchesHookIntegration.t.sol # Fork integration tests (7 tests)

deployments/
└── v4-tranches-unichain-sepolia.json  # Deployed addresses
```
