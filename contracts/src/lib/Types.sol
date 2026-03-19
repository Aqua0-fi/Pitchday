// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title Types
/// @author Aqua0 Team
/// @notice Shared type definitions for Aqua0 protocol

/// @notice Rebalance status enumeration
enum RebalanceStatus {
    PENDING, // Rebalance triggered, awaiting execution
    DOCKED, // Source strategy docked, ready for bridging
    BRIDGING, // Tokens being bridged via Stargate
    COMPLETED, // Rebalance completed successfully
    FAILED // Rebalance failed
}

/// @notice Rebalance operation structure
struct RebalanceOperation {
    address lpAccount; // LP Smart Account address
    uint32 srcChainId; // Source chain ID
    uint32 dstChainId; // Destination chain ID
    address token; // Token being rebalanced
    uint256 amount; // Amount to rebalance
    bytes32 messageGuid; // LayerZero message GUID (set after bridging)
    RebalanceStatus status; // Current status
    uint256 initiatedAt; // Timestamp when triggered
    uint256 completedAt; // Timestamp when completed (0 if pending)
}

/// @notice Chain configuration
struct ChainConfig {
    uint32 chainId; // EVM chain ID
    uint32 lzEid; // LayerZero endpoint ID
    address aquaRouter; // AquaRouter address on this chain
    address stargatePool; // Stargate USDC pool on this chain
    bool enabled; // Whether this chain is enabled
}

/// @notice Supported chains (Phase 1)
/// Base: chainId=8453, lzEid=30184
/// Arbitrum: chainId=42161, lzEid=30110
