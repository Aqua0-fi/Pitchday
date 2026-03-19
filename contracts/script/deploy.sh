#!/usr/bin/env bash
set -euo pipefail

# ── Aqua0 Production Deployment Script ──────────────────────────────────────
# Usage:
#   CHAIN=base DEPLOYER_PRIVATE_KEY=$KEY bash script/deploy.sh [--dry-run] [--no-verify]
#   CHAIN=unichain DEPLOYER_PRIVATE_KEY=$KEY bash script/deploy.sh [--dry-run] [--no-verify]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Parse flags ─────────────────────────────────────────────────────────────
VERIFY=true
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --no-verify) VERIFY=false ;;
        --dry-run)   DRY_RUN=true ;;
        *)           echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# ── Validate CHAIN ──────────────────────────────────────────────────────────
if [[ -z "${CHAIN:-}" ]]; then
    echo "Error: CHAIN env var is required (base or unichain)"
    exit 1
fi

if [[ "$CHAIN" != "base" && "$CHAIN" != "unichain" ]]; then
    echo "Error: CHAIN must be 'base' or 'unichain', got '$CHAIN'"
    exit 1
fi

# ── Validate DEPLOYER_PRIVATE_KEY ───────────────────────────────────────────
if [[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]; then
    echo "Error: DEPLOYER_PRIVATE_KEY env var is required"
    exit 1
fi

# ── Resolve RPC URL ─────────────────────────────────────────────────────────
if [[ "$CHAIN" == "base" ]]; then
    RPC_URL="${BASE_RPC_URL:-}"
    if [[ -z "$RPC_URL" ]]; then
        echo "Error: BASE_RPC_URL env var is required for Base deployment"
        exit 1
    fi
else
    RPC_URL="${UNICHAIN_RPC_URL:-}"
    if [[ -z "$RPC_URL" ]]; then
        echo "Error: UNICHAIN_RPC_URL env var is required for Unichain deployment"
        exit 1
    fi
fi

# ── Derive deployer address ─────────────────────────────────────────────────
DEPLOYER_ADDRESS=$(cast wallet address "$DEPLOYER_PRIVATE_KEY")

# ── Pre-flight balance check ────────────────────────────────────────────────
BALANCE_WEI=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL")
BALANCE_ETH=$(cast from-wei "$BALANCE_WEI")

# Check minimum balance (0.01 ETH)
MIN_BALANCE_WEI="100000000000000"
if [[ $(echo "$BALANCE_WEI < $MIN_BALANCE_WEI" | bc 2>/dev/null || python3 -c "print(int($BALANCE_WEI < $MIN_BALANCE_WEI))") == "1" ]]; then
    echo "Error: Deployer balance too low"
    echo "  Address: $DEPLOYER_ADDRESS"
    echo "  Balance: $BALANCE_ETH ETH"
    echo "  Minimum: 0.001 ETH"
    exit 1
fi

# ── Pre-flight summary ─────────────────────────────────────────────────────
echo "============================================"
echo "  Aqua0 Production Deployment"
echo "============================================"
echo "  Chain:    $CHAIN"
echo "  Deployer: $DEPLOYER_ADDRESS"
echo "  Balance:  $BALANCE_ETH ETH"
echo "  Factory:  ${FACTORY_VERSION:-v1}"
echo "  Verify:   $VERIFY"
echo "  Dry run:  $DRY_RUN"
echo "============================================"
echo ""

# ── Build forge script command ──────────────────────────────────────────────
FORGE_CMD=(
    forge script script/Deploy.s.sol:Deploy
    --rpc-url "$RPC_URL"
    --slow
    -vvvv
)

if [[ "$DRY_RUN" == "false" ]]; then
    FORGE_CMD+=(--broadcast)
fi

if [[ "$VERIFY" == "true" ]]; then
    if [[ -z "${ETHERSCAN_API_KEY:-}" ]]; then
        echo "Error: ETHERSCAN_API_KEY env var is required for verification"
        exit 1
    fi

    FORGE_CMD+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

# ── Run deployment ──────────────────────────────────────────────────────────
echo "Running: ${FORGE_CMD[*]}"
echo ""

cd "$PROJECT_DIR"
"${FORGE_CMD[@]}"

# ── Print deployed addresses ────────────────────────────────────────────────
DEPLOY_JSON="./deployments/$CHAIN.json"

if [[ -f "$DEPLOY_JSON" ]]; then
    echo ""
    echo "============================================"
    echo "  Deployed Addresses ($CHAIN)"
    echo "============================================"
    echo ""
    cat "$DEPLOY_JSON"
    echo ""
    echo ""
    echo "Addresses written to: $DEPLOY_JSON"
else
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "Dry run complete — no addresses written."
    else
        echo ""
        echo "Warning: $DEPLOY_JSON not found after deployment."
    fi
fi
