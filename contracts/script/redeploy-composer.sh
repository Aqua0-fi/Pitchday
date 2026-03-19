#!/usr/bin/env bash
set -euo pipefail

# ── Aqua0 Composer Redeployment Script ──────────────────────────────────
# Redeploys LZ Composer (native ETH wrapping fix + chain-specific LZ endpoint)
# and swaps it in BridgeRegistry.
#
# Usage:
#   CHAIN=base DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-composer.sh [--dry-run] [--no-verify]
#   CHAIN=unichain DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-composer.sh [--dry-run] [--no-verify]

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
        echo "Error: BASE_RPC_URL env var is required for Base"
        exit 1
    fi
else
    RPC_URL="${UNICHAIN_RPC_URL:-}"
    if [[ -z "$RPC_URL" ]]; then
        echo "Error: UNICHAIN_RPC_URL env var is required for Unichain"
        exit 1
    fi
fi

# ── Derive deployer address ─────────────────────────────────────────────────
DEPLOYER_ADDRESS=$(cd /tmp && cast wallet address "$DEPLOYER_PRIVATE_KEY")

# ── Pre-flight: show old address ────────────────────────────────────────────
DEPLOY_JSON="$PROJECT_DIR/deployments/$CHAIN.json"
OLD_COMPOSER=$(cd /tmp && python3 -c "import json; print(json.load(open('$DEPLOY_JSON'))['composer'])")
BRIDGE_REGISTRY=$(cd /tmp && python3 -c "import json; print(json.load(open('$DEPLOY_JSON'))['bridgeRegistry'])")

echo "============================================"
echo "  Aqua0 Composer Redeployment"
echo "============================================"
echo "  Chain:            $CHAIN"
echo "  Deployer:         $DEPLOYER_ADDRESS"
echo "  Old Composer:     $OLD_COMPOSER"
echo "  BridgeRegistry:   $BRIDGE_REGISTRY"
echo "  Verify:           $VERIFY"
echo "  Dry run:          $DRY_RUN"
echo "============================================"
echo ""

# ── Build forge script command ──────────────────────────────────────────────
FORGE_CMD=(
    forge script script/RedeployComposer.s.sol:RedeployComposer
    --rpc-url "$RPC_URL"
    --slow
    -vvvv
)

if [[ "$DRY_RUN" == "false" ]]; then
    FORGE_CMD+=(--broadcast)

    if [[ "$VERIFY" == "true" ]]; then
        if [[ -z "${ETHERSCAN_API_KEY:-}" ]]; then
            echo "Warning: ETHERSCAN_API_KEY not set, skipping verification"
        else
            FORGE_CMD+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
        fi
    fi
fi

# ── Run deployment ──────────────────────────────────────────────────────────
echo "Running: ${FORGE_CMD[*]}"
echo ""

cd "$PROJECT_DIR"
"${FORGE_CMD[@]}"

# ── Print result ────────────────────────────────────────────────────────────
if [[ -f "$DEPLOY_JSON" ]]; then
    NEW_COMPOSER=$(cd /tmp && python3 -c "import json; print(json.load(open('$DEPLOY_JSON'))['composer'])")

    echo ""
    echo "============================================"
    echo "  Composer Redeployed ($CHAIN)"
    echo "============================================"
    echo "  Old: $OLD_COMPOSER"
    echo "  New: $NEW_COMPOSER"
    echo ""
    echo "  Updated: $DEPLOY_JSON"
    echo "============================================"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "Dry run — no on-chain changes made."
    fi
fi
