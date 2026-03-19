# CLAUDE.md — Aqua0 Contracts

This file provides context for AI assistants (Claude, Cursor, Copilot, etc.) working on the Aqua0 smart contracts codebase.

## Project Overview

Aqua0 is a **cross-chain shared liquidity protocol** built on 1inch Aqua that enables liquidity providers (LPs) to deploy trading strategies across multiple blockchains through virtual balance accounting. The protocol is **non-custodial by design** — funds remain in LP-controlled accounts, never in protocol custody.

### Core Innovation

Instead of moving liquidity to where it's needed, Aqua0 brings operations to where the liquidity is. One $100k deposit can simultaneously back strategies on Base, Unichain, and Arbitrum through virtual balance tracking.

## Quick Reference

### Build & Test Commands

```bash
# Build contracts
bun run build        # or: forge build

# Run all unit tests (offline, no RPC needed)
bun run test         # or: FOUNDRY_OFFLINE=true forge test -vvv

# Run fork tests against real mainnet (requires RPC URLs)
BASE_RPC_URL=<url> UNICHAIN_RPC_URL=<url> forge test --match-path test/CrosschainFork.t.sol -vvv

# Run specific test by regex
FOUNDRY_OFFLINE=true forge test --match-test <Regex>

# Run fuzz tests only
FOUNDRY_OFFLINE=true forge test --match-test testFuzz

# Format check (CI enforces this)
bun run fmt:check    # or: forge fmt --check

# Apply formatting
bun run fmt          # or: forge fmt

# Clean build artifacts
forge clean
```

### Local Development (Anvil Fork)

```bash
# Fork Base mainnet, deploy all contracts, fund account, keep Anvil alive
bun run local

# Fork Unichain mainnet instead
bun run local:unichain

# Deploy only (Anvil exits after script completes)
bun run local:deploy
bun run local:deploy:unichain

# Kill Anvil
bun run local:down

# Addresses are written to deployments/localhost.json
cat deployments/localhost.json
```

The deploy script auto-detects the chain (Base=8453, Unichain=130) and sets up two test flows:

**LP flow** (deployer = Anvil account #0):
1. Deploys AccountFactory, Rebalancer, StargateAdapter, Composer, AquaAdapter
2. Creates a sample account with composer and rebalancer wired
3. Approves both WETH and USDC for Aqua
4. Funds the account with 10 WETH + 100k USDC
5. Ships a sample WETH strategy (5 ETH) — account can ship/dock more strategies

**Swapper flow** (swapper = Anvil account #1):
1. Funds swapper with 10 WETH + 100k USDC
2. Approves SwapVM Router and Aqua for both tokens
3. A WETH strategy is already active — swapper can call `SwapVMRouter.swap()` against it

Key JSON fields: `sampleAccount`, `swapper`, `swapVMRouter`, `wethStrategyHash`.

Env vars: `BASE_RPC_URL`, `UNICHAIN_RPC_URL`, `ANVIL_PORT` (default 8545), `FACTORY_VERSION` (default "v1" — bump to redeploy AccountFactory on a chain where a previous version exists).

### Key Directories

```
contracts/
├── src/
│   ├── lp/                  # Account + AccountFactory (LP smart accounts)
│   ├── aqua/                # AquaAdapter (optional Aqua wrapper)
│   ├── bridge/              # StargateAdapter + Composer
│   ├── rebalancer/          # Cross-chain rebalancing orchestration
│   ├── interface/           # IAqua, IStargate, IStargateAdapter, ISwapVMRouter, IAccount
│   └── lib/                 # Errors, Events, Types
├── test/
│   ├── utils/               # SwapVMProgramHelper, AccountTestHelper (test-only)
│   ├── LPAccount.t.sol        # Account unit tests
│   ├── LPSmartAccountFactory.t.sol  # AccountFactory unit tests
│   ├── Rebalancer.t.sol     # Rebalancer unit tests
│   ├── AquaAdapter.t.sol    # AquaAdapter unit tests
│   ├── BridgeAdapters.t.sol # StargateAdapter + Composer tests
│   ├── AccountCrosschain.t.sol # onCrosschainDeposit tests
│   ├── ComposerDelivery.t.sol # End-to-end bridge delivery tests
│   ├── StrategyBuilderCrossVerify.t.sol # Cross-verify strategy encoding with TS builder
│   ├── CrosschainFork.t.sol # Fork tests (real Aqua/SwapVM/Stargate)
│   └── AMMStrategyFork.t.sol # Fork tests (Constant Product + StableSwap templates)
├── script/
│   ├── DeployBase.s.sol     # Shared constants + _buildFactorySalt (version from FACTORY_VERSION env)
│   ├── Deploy.s.sol         # Production deploy (inherits DeployBase)
│   ├── DeployLocal.s.sol    # Local Anvil deploy (inherits DeployBase)
│   └── local-deploy.sh      # Shell orchestration (Anvil + deploy + fund)
├── deployments/             # Generated deployment addresses (gitignored)
├── foundry.toml             # Foundry configuration (Solidity 0.8.33)
└── Aqua0_PRD.md             # Product Requirements Document (source of truth)
```

## Architecture

### Key Actors

| Actor | Role | Key Responsibilities |
|-------|------|---------------------|
| **LP** | End user | Creates Account, deposits tokens, activates strategies via `ship()` |
| **Trader** | Swap executor | Executes swaps via SwapVM, pays fees |
| **Rebalancer** | Backend service | Monitors utilization, triggers cross-chain rebalancing |

### Core Terminology

- **Maker**: Account address — `msg.sender` when calling Aqua's `ship()`. This is how Aqua identifies the LP.
- **App**: The first parameter to `ship()`. The Account passes `swapVMRouter` so balances are visible to the SwapVM Router during swaps: `_balances[account][swapVMRouter][strategyHash][token]`.
- **Strategy**: SwapVM bytecode program. `strategyHash = keccak256(strategyBytes)` (raw bytes, NOT `keccak256(abi.encode(...))`).
- **Virtual Balance**: Aqua's 4D accounting: `_balances[maker][app][strategyHash][token]`
- **Ship**: Activate strategy by creating virtual balance entries in Aqua
- **Dock**: Deactivate strategy by zeroing virtual balances (tokens stay in Account)

### Aqua's 4D Balance Model

```
_balances[maker][app][strategyHash][token]
```

- **maker** = `msg.sender` (the Account address)
- **app** = first param to `ship()` — the Account passes `swapVMRouter` (NOT `address(this)`)
- **strategyHash** = `keccak256(strategyBytes)` — computed by Aqua internally
- **token** = ERC20 token address

When Account calls `AQUA.ship(swapVMRouter, strategy, tokens, amounts)`:
- maker = Account (msg.sender)
- app = SwapVM Router (first param)
- The SwapVM Router queries `safeBalances(maker, address(this), ...)` where `address(this)` = router
- Both sides match: `_balances[account][router][hash][token]`
- The account can still dock because it's the maker calling `dock()`

### IAqua Interface (matches real 1inch Aqua)

```solidity
interface IAqua {
    function ship(address app, bytes memory strategy, address[] memory tokens, uint256[] memory amounts)
        external returns (bytes32 strategyHash);

    function dock(address app, bytes32 strategyHash, address[] memory tokens) external;

    function rawBalances(address maker, address app, bytes32 strategyHash, address token)
        external view returns (uint248 balance, uint8 tokensCount);

    function safeBalances(address maker, address app, bytes32 strategyHash, address token0, address token1)
        external view returns (uint256 balance0, uint256 balance1);
}
```

Key notes:
- `rawBalances()` returns `(uint248, uint8)` — `tokensCount = 0xff` means docked
- `dock()` requires the tokens array — Account stores tokens at ship-time in `_strategyTokens` mapping
- `strategyHash = keccak256(strategy)` — NOT `keccak256(abi.encode(strategy))`

### Data Flow

```
LP Owner EOA
    │
    ▼
Account (via AccountFactory)  ──► 1inch Aqua (ship/dock/rawBalances)
    │                                │
    ├─► Rebalancer (authorized)      ▼
    │       │                 SwapVM Router (executes swaps)
    │       ▼
    │   Stargate Bridge ◄──► LayerZero V2
    │       │
    │       ▼
    └─► Composer (destination chain) ──► Account.onCrosschainDeposit()
```

## Key Contracts

### Account.sol

Non-custodial LP account. Acts as "maker" in Aqua's registry and ships under the SwapVM Router's app namespace. Uses the Beacon Proxy pattern — all Account instances share the same implementation via UpgradeableBeacon. Upgrades via `AccountFactory.upgradeAccountImplementation(newImpl)` affect all accounts simultaneously.

**Initialization:** `initialize(owner, factory, aqua, swapVMRouter)` — called once after BeaconProxy deployment.

**Key state:**
- `owner` (storage) — Account owner, set in `initialize()`
- `factory` (storage) — Factory address, set in `initialize()`
- `aqua` (storage) — Aqua protocol address, set in `initialize()`
- `swapVMRouter` (settable) — SwapVM Router address, used as `app` in Aqua's 4D mapping so the router can find balances during swaps
- `stargateAdapter` (settable) — StargateAdapter address for bridge operations

**Key functions:**
- `ship(strategyBytes, tokens[], amounts[])` → `bytes32 strategyHash` — Activate strategy
- `dock(strategyHash)` — Deactivate strategy (auto-retrieves stored tokens)
- `onCrosschainDeposit(strategyBytes, tokens[], amounts[])` — Called by Composer after bridge
- `approveAqua(token, amount)` — Approve Aqua to pull tokens during swaps
- `setSwapVMRouter(address)` — Update the SwapVM Router address (onlyOwner)
- `setComposer(address)` — Set the bridge receiver for cross-chain deposits
- `setStargateAdapter(address)` — Set the StargateAdapter address (onlyOwner)
- `withdraw(token, amount)` / `withdrawETH(amount)` — Owner-only withdrawals
- `authorizeRebalancer(address)` / `revokeRebalancer()` — Rebalancer access control
- `rebalancerBridge(token, dstEid, amount, minAmount, composeGasLimit, composeGasValue, composeMsg)` — Bridge tokens via StargateAdapter (owner or rebalancer)
- `getRawBalance(strategyHash, token)` → `(uint248, uint8)` — Query Aqua balance (uses swapVMRouter as app)
- `getStrategyTokens(strategyHash)` → `address[]` — Get stored tokens for a strategy

**Token storage pattern:** When `ship()` is called, the tokens array is stored in `_strategyTokens[strategyHash]`. When `dock()` is called, it retrieves the stored tokens automatically. This means `dock()` callers don't need to supply the tokens array.

**Why app = swapVMRouter:** The SwapVM Router queries Aqua with `app = address(this)` (the router). If the account shipped with `app = address(this)` (the account), balances would be in a different namespace and swaps would see 0 balances. By shipping with `app = swapVMRouter`, both sides match.

### AccountFactory.sol

Factory for deploying Accounts with CreateX CREATE3 (deterministic addresses across chains). Inherits `Ownable`. Deploys BeaconProxy instances pointing to UpgradeableBeacon.

**Constructor:** `constructor(address _aqua, address _swapVMRouter, address _createX, address _accountImpl)`

**Key state:**
- `AQUA` (immutable) — Aqua protocol address
- `SWAP_VM_ROUTER` (immutable) — SwapVM Router address (passed to new accounts at creation)
- `CREATEX` (immutable) — CreateX factory for CREATE3 deployments (`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` on all chains)

**Key functions:**
- `createAccount(signature)` → `address account` — Signature-verified salt (`keccak256(signature)`), verified via SignatureChecker (supports both EOA and ERC-1271)
- `getAccount(owner, salt)` → `address`
- `isAccount(address)` → `bool`
- `upgradeAccountImplementation(newImpl)` — Upgrades beacon implementation (onlyOwner), affects all Account instances

**CREATE3 salt format (32 bytes):**
- Bytes 0-19: `address(this)` (factory) — permissioned deploy
- Byte 20: `0x00` — no cross-chain redeploy protection (`block.chainid` excluded)
- Bytes 21-31: `bytes11(keccak256(owner, salt))` — LP identity entropy

CREATE3 addresses depend only on deployer + salt (not bytecode or constructor args). Same factory address + same owner + same salt → same account address on any chain, regardless of AQUA or SWAP_VM_ROUTER addresses.

### Rebalancer.sol

Orchestrates cross-chain rebalancing operations. Deployed behind ERC1967Proxy (UUPS pattern). `initialize(owner, rebalancer)` called once after proxy deployment. Includes `__gap[48]` storage gap for upgradeability.

**Rebalancing flow (state machine):**
1. `triggerRebalance(lpAccount, srcChainId, dstChainId, token, amount)` → PENDING
2. `executeDock(operationId, strategyHash)` → DOCKED
3. `executeBridge(operationId, ...)` → calls `Account.rebalancerBridge()` to bridge tokens via StargateAdapter
4. `recordBridging(operationId, messageGuid)` → BRIDGING
5. `confirmRebalance(operationId)` → COMPLETED
6. `failRebalance(operationId, reason)` → FAILED (from any non-terminal state)

COMPLETED and FAILED are terminal states — no further transitions are allowed.

**Dock-Reship-Bridge Pattern (real-world rebalancing):**
When rebalancing a partial amount (e.g., move 300 of 1000 to another chain):
1. Dock the full strategy on source (Aqua requires full dock, zeroes all virtual balances)
2. Reship the remainder on source (e.g., 700) to re-activate that portion
3. Bridge the rebalance amount (e.g., 300) to destination via Stargate + compose
4. Composer receives on destination, calls `account.onCrosschainDeposit()` to ship into Aqua
Result: source has 700 virtual balance, destination has 300 virtual balance.

### StargateAdapter.sol

Token bridging via Stargate V2. The Stargate pool address is stored as an admin-settable storage variable (not immutable) so it can be updated if Stargate migrates pools. Pulls tokens from caller via `safeTransferFrom` + `forceApprove` pattern.

- `bridge(dstEid, recipient, amount, minAmount)` → `bytes32 guid`
- `bridgeWithCompose(dstEid, dstComposer, composeMsg, amount, minAmount)` → `bytes32 guid`
- `quoteBridgeFee(dstEid, recipient, amount, minAmount)` → `uint256 fee`
- `quoteBridgeWithComposeFee(...)` → `uint256 fee` — Quote fee for bridge-with-compose operations
- `setStargate(address)` — Update Stargate pool address (onlyOwner, nonReentrant, emits StargateSet)

### Composer.sol

Destination-side bridge receiver. Receives bridged tokens from Stargate and forwards them to the Account, then calls `onCrosschainDeposit()`. TOKEN, LZ_ENDPOINT, and STARGATE are admin-settable storage variables (not immutable) to support infrastructure migrations without redeployment.

- `lzCompose(from, guid, message, executor, extraData)` — LayerZero compose callback
- `setToken(address)` — Update bridged token address (onlyOwner, nonReentrant, emits TokenSet)
- `setLzEndpoint(address)` — Update LZ endpoint (onlyOwner, nonReentrant, emits LzEndpointSet)
- `setStargate(address)` — Update Stargate pool (onlyOwner, nonReentrant, emits ComposerStargateSet)

### AquaAdapter.sol (Optional)

Thin wrapper for Aqua interactions. When AquaAdapter calls Aqua, IT becomes the "app" (not the Account). Use Account directly in most cases.

## Deployed Contract Addresses

| Contract | Address | Chains |
|----------|---------|--------|
| 1inch Aqua | `0x499943E74FB0cE105688beeE8Ef2ABec5D936d31` | Base, Unichain |
| SwapVM Router | `0x8fDD04Dbf6111437B44bbca99C28882434e0958f` | Base, Unichain |
| CreateX | `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` | 150+ chains |
| Stargate ETH Pool (Base) | `0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7` | Base |
| Stargate ETH Pool (Unichain) | `0xe9aBA835f813ca05E50A6C0ce65D0D74390F7dE7` | Unichain |
| LayerZero EndpointV2 (Base) | `0x1a44076050125825900e736c501f859c50fE728c` | Base |
| LayerZero EndpointV2 (Unichain) | `0x6F475642a6e85809B1c36Fa62763669b1b48DD5B` | Unichain |
| WETH | `0x4200000000000000000000000000000000000006` | Base, Unichain |
| USDC (Base) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | Base |
| USDC (Unichain) | `0x078D782b760474a361dDA0AF3839290b0EF57AD6` | Unichain |

**LayerZero Endpoint IDs:** Base = 30184, Unichain = 30320
**Chain IDs:** Base = 8453, Unichain = 130

## Testing

### Test Categories

1. **Unit tests** — Mock Aqua, test each contract in isolation (e.g., `LPAccount.t.sol`, `BridgeAdapters.t.sol`)
2. **Integration tests** — End-to-end flows across multiple contracts (e.g., `RebalancerIntegration.t.sol`)
3. **Fork tests** — Real Aqua/SwapVM/Stargate on Base and Unichain mainnet forks (`CrosschainFork.t.sol`)
4. **Fuzz tests** — Property-based tests for amounts and edge cases (prefixed `testFuzz_`)

### Fork Tests (CrosschainFork.t.sol)

Fork tests skip gracefully when RPC URLs are not set. They exercise:
- Account creation via AccountFactory on Base
- Shipping real SwapVM orders to real Aqua
- Docking strategies (verifying `tokensCount = 0xff`)
- Full swap lifecycle (quote via SwapVM router)
- Cross-chain deposit via Composer on Unichain
- Full rebalance flow Base → Unichain (ship → dock → bridge → receive → confirm)
- Authorize/revoke rebalancer with real Aqua
- Stargate compose message sending (OFTSent event verification)

### SwapVMProgramHelper (test utility)

`test/utils/SwapVMProgramHelper.sol` builds valid SwapVM Order structs without importing the full swap-vm dependency tree. Key functions:
- `buildMinimalOrder(maker)` — simplest XYC swap program
- `buildAMMOrder(maker, salt)` — XYC swap + salt for uniqueness
- `buildConstantProductProgram(token0, token1, balance0, balance1, feeBps)` — Constant Product (x*y=k) program
- `buildStableSwapProgram(token0, token1, balance0, balance1, linearWidth, rate0, rate1, feeBps)` — StableSwap (PeggedSwap) program
- `buildAquaOrder(maker, program)` — Wrap raw program bytes into an Aqua Order
- `buildAquaTakerData()` — Minimal taker data for Aqua swaps (22 bytes)
- `encodeStrategy(order)` — `abi.encode(order.maker, order.traits, order.data)`
- `computeStrategyHash(bytes)` — `keccak256(strategyBytes)`

### Conventions

- **Test naming**: `test_<description>` for unit tests, `testFuzz_<description>` for fuzz tests, `testFork_<description>` for fork tests
- Use `bound()` over `vm.assume()` in fuzz tests
- Test both happy paths AND revert paths for every function
- Verify event emission with `vm.expectEmit` for state-changing operations
- Access control: test `onlyOwner`, `onlyOwnerOrRebalancer`, `onlyComposer`, `onlyBridgeExecutor`, `onlyRebalancer` modifiers

## Code Style

- **License**: `// SPDX-License-Identifier: MIT` required at top of every `.sol` file
- **Imports**: Use relative paths (`../`, `./`) for project contracts; use package-style absolute paths for dependencies (e.g., `@openzeppelin/...`)
- **Naming**: PascalCase for contracts/structs, camelCase for functions/variables, UPPER_SNAKE_CASE for constants and immutables
- **NatSpec**: Comprehensive NatSpec (`@notice`, `@param`, `@return`, `@dev`) on all public/external functions and custom errors
- **Errors**: Custom errors only — no `require` with string messages. Use `if (!condition) revert Errors.SomeError()` pattern consistently
- **Security**: Use OpenZeppelin's SafeERC20, ReentrancyGuard, and Ownable patterns
- **Formatting**: `forge fmt` enforced (see `foundry.toml` for line length and tab width)

## Solidity Best Practices

### Error Handling

- **Custom Errors**: Always use custom errors defined in `src/lib/Errors.sol` (gas-efficient, no string reverts)
- **Error Pattern**: Use `if (!condition) revert Errors.SomeError()` — this is the consistent pattern across the codebase
- **Try-Catch**: Use try-catch for all cross-contract calls (ERC20, Aqua, Stargate)
  ```solidity
  try external.call() returns (Type result) {
      // success path
  } catch {
      revert Errors.OperationFailed();
  }
  ```
- **Specific selectors**: In tests, use `vm.expectRevert(Errors.SomeError.selector)` — avoid generic `vm.expectRevert()` unless error data is genuinely unavailable

### Function Ordering

Functions should be ordered within contracts as:

1. External functions
2. Public functions
3. Internal functions
4. Private functions

Within each group, order by: view/pure first, then state-changing.

### Security Patterns

- **Checks-Effects-Interactions (CEI)**: Always validate, update state, then call external contracts
- **Reentrancy Protection**: Use `nonReentrant` modifier on all state-changing external functions
- **Access Control**: Use `onlyOwner`, `onlyOwnerOrRebalancer`, `onlyComposer`, `onlyBridgeExecutor`, `onlyRebalancer` modifiers
- **SafeERC20**: All ERC20 interactions must use `SafeERC20` wrappers (`safeTransfer`, `safeTransferFrom`, `forceApprove`) — raw `transfer`/`transferFrom` calls can silently fail on non-standard tokens
- **Sanity Checks**: Validate addresses (`!= address(0)`), amounts (`> 0`), array bounds, and array length matching
- **State Checks**: Validate strategy existence before dock operations, check rebalance state machine transitions

### Storage Optimization

- **Variable Packing**: Pack related variables in same storage slot (e.g., `bool` + `uint48` + `address` = 1 slot)
- **Struct Ordering**: Order struct fields by size (largest first) to minimize slots
- **Immutable Variables**: Use `immutable` for values that never change (AQUA, FACTORY in Account). Bridge infrastructure addresses (TOKEN, LZ_ENDPOINT, STARGATE in Composer; stargate in StargateAdapter) are admin-settable storage variables to support infrastructure migrations without redeployment.

### Cross-Chain Security

- **Slippage Protection**: Always validate `minAmountOut` in bridge operations
- **Message Integrity**: Verify LayerZero GUID is non-zero, track pending operations per rebalance
- **Bridge Module Checks**: Validate bridge is active before calling
- **LayerZero Specific**:
  - Validate `lzComposeGas > 0` for compose operations
  - Encode compose options correctly (TYPE_3 executor options)
  - Composer decodes LZ compose messages inline using `abi.decode` on the OFT compose message bytes directly (no external codec library)

### Critical Invariants

These must hold at all times:

1. **Fund Conservation**: Funds remain in LP accounts; protocol never has custody
2. **Authorization**: Only account owner and authorized rebalancer can perform privileged operations
3. **Slippage Bounds**: Bridge operations enforce `minAmountOut` or revert
4. **Message Integrity**: Cross-chain GUIDs are non-zero and tracked per rebalance operation (no replay)
5. **State Consistency**: Rebalance state machine transitions enforced (PENDING → DOCKED → BRIDGING → COMPLETED)

## Testing Best Practices

### Fuzz Testing Configuration

Configuration in `foundry.toml`:
- `runs = 1000` — Each fuzz test runs 1000 iterations (CI uses 256 for speed)
- `seed = '0x1'` — Deterministic fuzzing for reproducible results
- `failure_persist_dir = "test/fuzz-failures"` — Saves counterexamples for regression

Best practices:
- Use `bound(value, min, max)` instead of `vm.assume()` to avoid rejection issues
- Use smaller types (`uint128`, `uint16`) for better input space coverage
- Test invariants (balance conservation, access control) not specific values
- Example: `testFuzz_ship(uint256 _amount)` tests shipping with bounded random amounts

### Test Maintenance

**When adding new features:**
1. Add security test if it involves funds, authorization, or cross-chain ops
2. Add fuzz test for numerical parameters (amounts, percentages)
3. Verify all critical invariants still hold
4. Run `FOUNDRY_OFFLINE=true forge test -vvv` before committing

**When modifying errors:**
- Update test expectations to match actual error selectors
- Use `vm.expectRevert(abi.encodeWithSelector(Errors.SomeError.selector, param))` for parameterized errors

**When changing cross-chain integration:**
- Update CrosschainFork.t.sol to match new message formats
- Verify compose message encoding round-trips correctly
- Check LayerZero options format (executor gas options)

## Security Checklist

Before any PR:
- [ ] Tests cover happy path + failure/revert modes
- [ ] CEI pattern enforced (Checks-Effects-Interactions)
- [ ] No custody creep (funds stay in Accounts)
- [ ] Custom errors used (not string reverts)
- [ ] Events emitted for state changes
- [ ] Reentrancy protection where needed
- [ ] Slippage protection with `minAmountOut`
- [ ] Cross-chain message GUIDs tracked (no replay)
- [ ] Access control modifiers tested
- [ ] Fuzz tests added for numerical parameters
- [ ] Cross-chain security patterns followed

## External Dependencies

| Dependency | Purpose | Key Info |
|------------|---------|----------|
| 1inch Aqua | Virtual balance + swaps | [github.com/1inch/aqua](https://github.com/1inch/aqua) |
| 1inch SwapVM | Bytecode swap execution | [github.com/1inch/swap-vm](https://github.com/1inch/swap-vm) |
| CreateX | CREATE3 deterministic deployment | [github.com/pcaversaccio/createx](https://github.com/pcaversaccio/createx) |
| LayerZero V2 | Cross-chain messaging | [docs.layerzero.network](https://docs.layerzero.network) |
| Stargate V2 | Token bridging | [docs.stargate.finance](https://docs.stargate.finance) |
| OpenZeppelin | Ownable, ReentrancyGuard, SafeERC20 | v5.x |

## Known Technical Debt

### Extract bridge execution logic from Account

**Priority**: Low — revisit before adding a 3rd bridge protocol.

`Account.sol` currently mixes LP account management (ship/dock, Aqua approvals, withdrawals) with bridge-specific execution logic:
- Protocol-specific functions: `bridgeCCTP()`, `rebalancerBridge()` (Stargate)
- Bridge key constants: `STARGATE_KEY`, `CCTP_KEY`
- Per-bridge token approval + adapter call patterns duplicated in each function

Adding a new bridge protocol requires modifying `Account.sol` and upgrading the beacon implementation (affecting all deployed accounts).

**Proposed direction**: Introduce a `BridgeExecutor` contract between Account and BridgeRegistry. Account would expose a single generic `bridge()` entry point; the executor handles adapter lookup, token approval, and protocol-specific call dispatch. BridgeRegistry already does the lookup — what's missing is a unified execution layer so the Account doesn't need to know the shape of each bridge's call.

**Files involved**: `src/lp/Account.sol`, `src/bridge/BridgeRegistry.sol`

## Source of Truth

The **Technical Architecture** section in `Aqua0_PRD.md` is authoritative for contract scope and behavior. If any other documentation conflicts, the PRD takes precedence.
