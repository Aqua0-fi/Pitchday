#!/bin/bash
# Run 5 demo swaps one at a time with spacing between each
# Usage: cd contracts && bash script/run-demo-swaps.sh

set -e
source .env

RPC="https://sepolia.unichain.org"
PK="$DEPLOYER_PRIVATE_KEY"
ROUTER="0x84175aA7EfD2805Ff8Dc2CF49EC3990b50daf3a1"
MUSDC="0x73c56ddD816e356387Caf740c804bb9D379BE47E"
MWETH="0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad"

# Approve router (infinite) for both tokens
echo "=== Approving router for mUSDC..."
cast send $MUSDC "approve(address,uint256)" $ROUTER $(cast max-uint) --rpc-url $RPC --private-key $PK
sleep 3

echo "=== Approving router for mWETH..."
cast send $MWETH "approve(address,uint256)" $ROUTER $(cast max-uint) --rpc-url $RPC --private-key $PK
sleep 3

# Min/Max sqrtPriceLimitX96
MIN_SQRT="4295128740"
MAX_SQRT="1461446703485210103287273052203988822378723970341"

# Hooks
HOOK_CONS="0x16326eCA33f5B28e3D572Ed38B066919E8E555C5"
HOOK_STD="0x8E104beAC6dA7351B00b36E9f2B248F2BfD595c5"
HOOK_AGG="0xA6a0b93092aF21cBAB5f69C243f0dA2cF466D5c5"
HOOK_TRAD="0xAf99B4dBAeEfAeC6AbCb1018290ea705B3C895c5"

swap() {
    local HOOK=$1 FEE=$2 TICK=$3 ZERO=$4 AMOUNT=$5 LABEL=$6
    echo ""
    echo "=== $LABEL ==="
    cast send $ROUTER \
        "swap((address,address,uint24,int24,address),(bool,int256,uint160),(bool,bool),bytes)" \
        "($MUSDC,$MWETH,$FEE,$TICK,$HOOK)" \
        "($ZERO,$AMOUNT,$( [ "$ZERO" = "true" ] && echo $MIN_SQRT || echo $MAX_SQRT ))" \
        "(false,false)" \
        "0x" \
        --rpc-url $RPC --private-key $PK
    echo "  Done!"
    sleep 5
}

echo ""
echo "========================================"
echo "  5 Demo Swaps (round-robin, 5s apart)"
echo "========================================"

# Swap 1: Conservative — 500 mUSDC -> mWETH
swap $HOOK_CONS 500 10 true "-500000000000000000000" "Swap 1: 500 mUSDC -> mWETH via Conservative (0.05%)"

# Swap 2: Standard — 0.1 mWETH -> mUSDC
swap $HOOK_STD 3000 60 false "-100000000000000000" "Swap 2: 0.1 mWETH -> mUSDC via Standard (0.30%)"

# Swap 3: Aggressive — 1000 mUSDC -> mWETH
swap $HOOK_AGG 10000 200 true "-1000000000000000000000" "Swap 3: 1000 mUSDC -> mWETH via Aggressive (1.00%)"

# Swap 4: Traditional — 0.05 mWETH -> mUSDC
swap $HOOK_TRAD 3000 60 false "-50000000000000000" "Swap 4: 0.05 mWETH -> mUSDC via Traditional (0.30%)"

# Swap 5: Conservative — 200 mUSDC -> mWETH
swap $HOOK_CONS 500 10 true "-200000000000000000000" "Swap 5: 200 mUSDC -> mWETH via Conservative (0.05%)"

echo ""
echo "========================================"
echo "  All 5 swaps complete!"
echo "========================================"
