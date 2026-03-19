// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title Events
/// @author Aqua0 Team
/// @notice Event definitions for Aqua0 protocol contracts
/// @dev These are events emitted by AQUA0 contracts, NOT the 1inch AquaRouter.
///
///      For indexing purposes:
///      - AquaRouter events (ship/dock/swap) are indexed from the 1inch contract directly
///      - LayerZero/Stargate events are indexed from their respective contracts
///      - These events are for Aqua0-specific contracts (LPAccountFactory, Rebalancer, etc.)
library Events {
    // ============================================
    // LP ACCOUNT FACTORY EVENTS
    // ============================================

    /// @notice Emitted when a new LP Smart Account is created
    /// @param account The created account address
    /// @param owner The owner (LP's EOA)
    /// @param salt The CREATE2 salt used
    event AccountCreated(address indexed account, address indexed owner, bytes32 salt);

    // ============================================
    // LP SMART ACCOUNT EVENTS
    // ============================================

    /// @notice Emitted when rebalancer is authorized
    /// @param account The LP Smart Account
    /// @param rebalancer The authorized rebalancer address
    event RebalancerAuthorized(address indexed account, address indexed rebalancer);

    /// @notice Emitted when rebalancer authorization is revoked
    /// @param account The LP Smart Account
    event RebalancerRevoked(address indexed account);

    /// @notice Emitted when the SwapVM Router address is updated on an Account
    /// @param oldRouter The previous router address
    /// @param newRouter The new router address
    event SwapVMRouterSet(address indexed oldRouter, address indexed newRouter);

    /// @notice Emitted when the StargateAdapter address is updated on an Account
    /// @param oldAdapter The previous adapter address
    /// @param newAdapter The new adapter address
    event StargateAdapterSet(address indexed oldAdapter, address indexed newAdapter);

    /// @notice Emitted when the Account implementation is upgraded via beacon
    /// @param newImplementation The new implementation address
    event AccountImplementationUpgraded(address indexed newImplementation);

    /// @notice Emitted when tokens are deposited to LP Smart Account
    /// @param account The LP Smart Account
    /// @param token The token deposited
    /// @param amount The amount deposited
    /// @param from The depositor address
    event Deposited(address indexed account, address indexed token, uint256 amount, address from);

    /// @notice Emitted when tokens are withdrawn from LP Smart Account
    /// @param account The LP Smart Account
    /// @param token The token withdrawn
    /// @param amount The amount withdrawn
    /// @param to The recipient address
    event Withdrawn(address indexed account, address indexed token, uint256 amount, address to);

    // ============================================
    // REBALANCER EVENTS
    // ============================================

    /// @notice Emitted when a rebalance operation is triggered
    /// @param operationId Unique operation identifier
    /// @param lpAccount The LP Smart Account being rebalanced
    /// @param srcChainId Source chain ID
    /// @param dstChainId Destination chain ID
    /// @param token The token being rebalanced
    /// @param amount The amount being rebalanced
    event RebalanceTriggered(
        bytes32 indexed operationId,
        address indexed lpAccount,
        uint32 srcChainId,
        uint32 dstChainId,
        address token,
        uint256 amount
    );

    /// @notice Emitted when a rebalance operation completes
    /// @param operationId The operation identifier
    /// @param messageGuid The LayerZero message GUID (if cross-chain)
    event RebalanceCompleted(bytes32 indexed operationId, bytes32 indexed messageGuid);

    /// @notice Emitted when a rebalance operation fails
    /// @param operationId The operation identifier
    /// @param reason The failure reason
    event RebalanceFailed(bytes32 indexed operationId, string reason);

    // ============================================
    // BRIDGE ADAPTER EVENTS
    // ============================================

    /// @notice Emitted when a LayerZero peer is set
    /// @param eid The endpoint ID
    /// @param peer The peer address (as bytes32)
    event PeerSet(uint32 indexed eid, bytes32 peer);

    /// @notice Emitted when the Stargate address is updated on StargateAdapter
    /// @param oldStargate The previous Stargate address
    /// @param newStargate The new Stargate address
    event StargateSet(address indexed oldStargate, address indexed newStargate);

    /// @notice Emitted when a cross-chain message is sent via LayerZero
    /// @param dstEid Destination endpoint ID
    /// @param guid Message GUID for tracking
    /// @param message The message bytes
    event MessageSent(uint32 indexed dstEid, bytes32 indexed guid, bytes message);

    /// @notice Emitted when tokens are bridged via Stargate
    /// @param dstEid Destination endpoint ID
    /// @param recipient Recipient address on destination chain
    /// @param amountIn Amount sent
    /// @param amountOut Amount received (after fees)
    /// @param guid Message GUID for tracking
    event TokensBridged(
        uint32 indexed dstEid, address indexed recipient, uint256 amountIn, uint256 amountOut, bytes32 guid
    );

    // ============================================
    // COMPOSER EVENTS
    // ============================================

    /// @notice Emitted when the token address is updated on Composer
    /// @param oldToken The previous token address
    /// @param newToken The new token address
    event TokenSet(address indexed oldToken, address indexed newToken);

    /// @notice Emitted when the LZ endpoint address is updated on Composer
    /// @param oldEndpoint The previous endpoint address
    /// @param newEndpoint The new endpoint address
    event LzEndpointSet(address indexed oldEndpoint, address indexed newEndpoint);

    /// @notice Emitted when the Stargate address is updated on Composer
    /// @param oldStargate The previous Stargate address
    /// @param newStargate The new Stargate address
    event ComposerStargateSet(address indexed oldStargate, address indexed newStargate);

    /// @notice Emitted when the WETH address is updated on Composer
    /// @param oldWeth The previous WETH address
    /// @param newWeth The new WETH address
    event ComposerWethSet(address indexed oldWeth, address indexed newWeth);

    /// @notice Emitted when a compose message is received and processed by Composer
    /// @param guid The LayerZero message GUID
    /// @param from The Stargate/OFT address that sent the message
    /// @param amount The amount of tokens received
    /// @param strategyHash The strategy hash from the account's Aqua ship
    event ComposeReceived(bytes32 indexed guid, address indexed from, uint256 amount, bytes32 strategyHash);

    // ============================================
    // BRIDGE REGISTRY EVENTS
    // ============================================

    /// @notice Emitted when an adapter is set in the BridgeRegistry
    /// @param key The adapter key
    /// @param adapter The adapter address
    event AdapterSet(bytes32 indexed key, address indexed adapter);

    /// @notice Emitted when an adapter is removed from the BridgeRegistry
    /// @param key The adapter key
    /// @param oldAdapter The removed adapter address
    event AdapterRemoved(bytes32 indexed key, address indexed oldAdapter);

    /// @notice Emitted when a composer is added to the BridgeRegistry
    /// @param composer The composer address
    event ComposerAdded(address indexed composer);

    /// @notice Emitted when a composer is removed from the BridgeRegistry
    /// @param composer The composer address
    event ComposerRemoved(address indexed composer);

    // ============================================
    // CCTP ADAPTER EVENTS
    // ============================================

    /// @notice Emitted when the TokenMessenger address is updated on CCTPAdapter
    /// @param oldMessenger The previous messenger address
    /// @param newMessenger The new messenger address
    event TokenMessengerSet(address indexed oldMessenger, address indexed newMessenger);

    /// @notice Emitted when tokens are bridged via CCTP
    /// @param dstDomain Destination CCTP domain ID
    /// @param mintRecipient Recipient address on destination chain
    /// @param token The token bridged
    /// @param amount The amount bridged
    /// @param nonce The CCTP message nonce
    event CCTPBridged(
        uint32 indexed dstDomain, address indexed mintRecipient, address token, uint256 amount, uint64 nonce
    );

    // ============================================
    // CCTP COMPOSER EVENTS
    // ============================================

    /// @notice Emitted when the MessageTransmitter address is updated on CCTPComposer
    /// @param oldTransmitter The previous transmitter address
    /// @param newTransmitter The new transmitter address
    event MessageTransmitterSet(address indexed oldTransmitter, address indexed newTransmitter);

    /// @notice Emitted when the token address is updated on CCTPComposer
    /// @param oldToken The previous token address
    /// @param newToken The new token address
    event CCTPComposerTokenSet(address indexed oldToken, address indexed newToken);

    /// @notice Emitted when a CCTP compose message is received and processed
    /// @param amount The amount of tokens received
    /// @param strategyHash The strategy hash from the account's Aqua ship
    event CCTPComposeReceived(uint256 amount, bytes32 indexed strategyHash);

    // ============================================
    // POOL REGISTRY EVENTS
    // ============================================

    /// @notice Emitted when a Stargate pool is registered for a token in StargateAdapter
    /// @param token The token address
    /// @param pool The Stargate pool address
    event StargatePoolRegistered(address indexed token, address indexed pool);

    /// @notice Emitted when a Stargate pool is removed from StargateAdapter
    /// @param token The token address
    /// @param pool The Stargate pool address
    event StargatePoolRemoved(address indexed token, address indexed pool);

    /// @notice Emitted when a Stargate pool is registered in Composer (pool → token mapping)
    /// @param stargatePool The Stargate pool address
    /// @param token The token address
    event ComposerPoolRegistered(address indexed stargatePool, address indexed token);

    /// @notice Emitted when a Stargate pool is removed from Composer
    /// @param stargatePool The Stargate pool address
    /// @param token The token address
    event ComposerPoolRemoved(address indexed stargatePool, address indexed token);
}
