#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CHAIN="${CHAIN:-base}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
RPC_URL="http://127.0.0.1:$ANVIL_PORT"

KEEP_ALIVE=false
ANVIL_PID=""

# Chain-specific fork RPC
case "$CHAIN" in
    base)
        FORK_RPC="${BASE_RPC_URL:-https://mainnet.base.org}"
        ;;
    unichain)
        FORK_RPC="${UNICHAIN_RPC_URL:-https://mainnet.unichain.org}"
        ;;
    *)
        echo "ERROR: Unsupported chain '$CHAIN'. Use 'base' or 'unichain'."
        exit 1
        ;;
esac

for arg in "$@"; do
    case $arg in
        --keep-alive) KEEP_ALIVE=true ;;
    esac
done

cleanup() {
    if [ -n "$ANVIL_PID" ] && kill -0 "$ANVIL_PID" 2>/dev/null; then
        echo "Stopping Anvil (PID $ANVIL_PID)..."
        kill "$ANVIL_PID"
    fi
}

if [ "$KEEP_ALIVE" = false ]; then
    trap cleanup EXIT
fi

cd "$PROJECT_DIR"
mkdir -p deployments

# ── Start Anvil ──────────────────────────────────────────────────────────────
echo "Starting Anvil (chain: $CHAIN, factory: ${FACTORY_VERSION:-v1}, fork: $FORK_RPC, port: $ANVIL_PORT)..."
anvil --fork-url "$FORK_RPC" --port "$ANVIL_PORT" --silent &
ANVIL_PID=$!

echo "Waiting for Anvil..."
SECONDS_WAITED=0
until cast block-number --rpc-url "$RPC_URL" &>/dev/null; do
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
    if [ "$SECONDS_WAITED" -ge 30 ]; then
        echo "ERROR: Anvil failed to start within 30s"
        exit 1
    fi
done
echo "Anvil ready (block $(cast block-number --rpc-url "$RPC_URL"))"

# ── Clear EIP-7702 delegation codes ──────────────────────────────────────────
# Anvil accounts on Base mainnet fork may have EIP-7702 delegation code which
# breaks ECDSA signature recovery (SignatureChecker tries ERC-1271 instead).
echo "Clearing EIP-7702 delegation codes..."
for addr in \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC \
  0x90F79bf6EB2c4f870365E785982E1f101E93b906 \
  0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; do
  cast rpc anvil_setCode "$addr" 0x --rpc-url "$RPC_URL" > /dev/null 2>&1
done

# ── Deploy contracts ─────────────────────────────────────────────────────────
echo "Deploying contracts..."
forge script script/DeployLocal.s.sol:DeployLocal \
    --rpc-url "$RPC_URL" \
    --broadcast \
    -vvv

# ── Fund USDC via Anvil storage manipulation ─────────────────────────────────
# The deployer has no USDC, so we set balances directly.  This tries common
# ERC20 balance mapping slots until balanceOf returns the expected value
# (same approach forge-std deal() uses internally).
ACCOUNT=$(jq -r .sampleAccount deployments/localhost.json)
SWAPPER=$(jq -r .swapper deployments/localhost.json)
USDC=$(jq -r .usdc deployments/localhost.json)
WETH=$(jq -r .weth deployments/localhost.json)

USDC_AMOUNT=100000000000  # 100,000 USDC (6 decimals)
USDC_SLOT=""              # cached after first successful probe

fund_erc20() {
    local token=$1 recipient=$2 amount=$3

    # If we already know the slot from a previous call, use it directly
    if [ -n "$USDC_SLOT" ]; then
        local storage_key hex_amount actual actual_num
        storage_key=$(cast index address "$recipient" "$USDC_SLOT")
        hex_amount=$(printf '0x%064x' "$amount")
        cast rpc anvil_setStorageAt "$token" "$storage_key" "$hex_amount" \
            --rpc-url "$RPC_URL" > /dev/null 2>&1
        actual=$(cast call "$token" "balanceOf(address)(uint256)" "$recipient" \
            --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
        actual_num=$(echo "$actual" | awk '{print $1}')
        if [ "$actual_num" = "$amount" ]; then
            return 0
        fi
    fi

    for slot in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 50 51; do
        local storage_key hex_amount actual actual_num
        storage_key=$(cast index address "$recipient" "$slot")
        hex_amount=$(printf '0x%064x' "$amount")

        cast rpc anvil_setStorageAt "$token" "$storage_key" "$hex_amount" \
            --rpc-url "$RPC_URL" > /dev/null 2>&1

        actual=$(cast call "$token" "balanceOf(address)(uint256)" "$recipient" \
            --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
        actual_num=$(echo "$actual" | awk '{print $1}')

        if [ "$actual_num" = "$amount" ]; then
            USDC_SLOT="$slot"  # cache for next call
            return 0
        fi

        # Reset slot before trying next
        cast rpc anvil_setStorageAt "$token" "$storage_key" \
            "0x0000000000000000000000000000000000000000000000000000000000000000" \
            --rpc-url "$RPC_URL" > /dev/null 2>&1
    done

    echo "  WARNING: Could not auto-fund USDC (no matching balance slot found)"
    return 1
}

echo "Funding USDC..."
fund_erc20 "$USDC" "$ACCOUNT" "$USDC_AMOUNT"
echo "  Account: $(echo "scale=2; $USDC_AMOUNT / 1000000" | bc) USDC"
fund_erc20 "$USDC" "$SWAPPER" "$USDC_AMOUNT"
echo "  Swapper: $(echo "scale=2; $USDC_AMOUNT / 1000000" | bc) USDC"

# ── Verify balances ──────────────────────────────────────────────────────────
echo ""
echo "=== Account (LP) ==="
ACCOUNT_WETH=$(cast call "$WETH" "balanceOf(address)(uint256)" "$ACCOUNT" --rpc-url "$RPC_URL" | awk '{print $1}')
ACCOUNT_USDC=$(cast call "$USDC" "balanceOf(address)(uint256)" "$ACCOUNT" --rpc-url "$RPC_URL" | awk '{print $1}')
echo "  WETH: $(echo "scale=4; $ACCOUNT_WETH / 1000000000000000000" | bc) ETH"
echo "  USDC: $(echo "scale=2; $ACCOUNT_USDC / 1000000" | bc) USDC"

STRATEGY_HASH=$(jq -r .wethStrategyHash deployments/localhost.json)
echo "  Shipped WETH strategy: $STRATEGY_HASH"

echo ""
echo "=== Swapper ==="
SWAPPER_WETH=$(cast call "$WETH" "balanceOf(address)(uint256)" "$SWAPPER" --rpc-url "$RPC_URL" | awk '{print $1}')
SWAPPER_USDC=$(cast call "$USDC" "balanceOf(address)(uint256)" "$SWAPPER" --rpc-url "$RPC_URL" | awk '{print $1}')
echo "  WETH: $(echo "scale=4; $SWAPPER_WETH / 1000000000000000000" | bc) ETH"
echo "  USDC: $(echo "scale=2; $SWAPPER_USDC / 1000000" | bc) USDC"

# ── Print addresses ──────────────────────────────────────────────────────────
echo ""
echo "=== Deployed Addresses ($CHAIN) ==="
jq . deployments/localhost.json
echo ""

if [ "$KEEP_ALIVE" = true ]; then
    echo "Anvil running on $RPC_URL (PID $ANVIL_PID). Press Ctrl+C to stop."
    wait "$ANVIL_PID"
fi
