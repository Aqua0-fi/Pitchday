// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title Errors
/// @author Aqua0 Team
/// @notice Custom error definitions for Aqua0 protocol
library Errors {
    // ============================================
    // GENERAL ERRORS
    // ============================================

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when input is invalid
    error InvalidInput();

    /// @notice Thrown when caller is not the owner
    error NotOwner();

    /// @notice Thrown when caller is not authorized
    error NotAuthorized();

    /// @notice Thrown when caller is not the rebalancer
    error NotRebalancer();

    // ============================================
    // ACCOUNT ERRORS
    // ============================================

    /// @notice Thrown when account already exists
    error AccountAlreadyExists();

    /// @notice Thrown when account is not found
    error AccountNotFound();

    /// @notice Thrown when transfer fails
    error TransferFailed();

    /// @notice Thrown when balance is insufficient
    error InsufficientBalance();

    // ============================================
    // STRATEGY ERRORS
    // ============================================

    /// @notice Thrown when strategy bytes are invalid
    error InvalidStrategyBytes();

    /// @notice Thrown when strategy is invalid or not found
    error InvalidStrategy();

    /// @notice Thrown when dock() is called but no tokens were stored for the strategy
    error StrategyTokensNotFound();

    // ============================================
    // REBALANCE ERRORS
    // ============================================

    /// @notice Thrown when rebalance operation is not found
    error RebalanceOperationNotFound();

    // ============================================
    // BRIDGE ERRORS
    // ============================================

    /// @notice Thrown when no peer is set for destination
    error NoPeerSet();

    /// @notice Thrown when bridge fee is insufficient
    error InsufficientBridgeFee();

    /// @notice Thrown when a signature is invalid
    error InvalidSignature();

    // ============================================
    // BRIDGE REGISTRY ERRORS
    // ============================================

    /// @notice Thrown when no adapter is registered for the given key
    error AdapterNotRegistered();

    /// @notice Thrown when trying to add a composer that is already trusted
    error ComposerAlreadyTrusted();

    /// @notice Thrown when trying to remove a composer that is not trusted
    error ComposerNotTrusted();

    // ============================================
    // CCTP ERRORS
    // ============================================

    /// @notice Thrown when the CCTP relay (receiveMessage) fails
    error CCTPRelayFailed();

    /// @notice Thrown when the CCTP burn (depositForBurnWithHook) fails
    error CCTPBurnFailed();

    /// @notice Thrown when composePayload does not match hookData in the CCTP message
    error HookDataMismatch();

    /// @notice Thrown when the CCTP message is too short to contain hookData
    error CCTPMessageTooShort();

    // ============================================
    // POOL REGISTRY ERRORS
    // ============================================

    /// @notice Thrown when no pool is registered for the given token or Stargate pool
    error PoolNotRegistered();

    /// @notice Thrown when attempting to register a pool that is already registered
    error PoolAlreadyRegistered();
}
