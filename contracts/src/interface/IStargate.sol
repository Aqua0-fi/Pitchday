// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IStargate
/// @author Aqua0 Team
/// @notice Minimal interface for Stargate V2 pool/router
/// @dev Based on Stargate V2 specification
interface IStargate {
    /// @notice Sends tokens cross-chain via Stargate
    /// @param _sendParam The parameters for the send operation
    /// @param _fee The messaging fee
    /// @param _refundAddress The address to refund excess fees
    /// @return receipt The messaging receipt
    /// @return amountOut The amount sent
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt, uint256 amountOut);

    /// @notice Quotes the fee for a send operation
    /// @param _sendParam The parameters for the send operation
    /// @param _payInLzToken Whether to pay in LZ token
    /// @return fee The quoted fee
    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken)
        external
        view
        returns (MessagingFee memory fee);

    /// @notice Gets the token address for this Stargate pool
    /// @return The token address
    function token() external view returns (address);
}

/// @notice Parameters for Stargate send operation
struct SendParam {
    uint32 dstEid; // Destination endpoint ID
    bytes32 to; // Recipient address (as bytes32)
    uint256 amountLD; // Amount in local decimals
    uint256 minAmountLD; // Minimum amount to receive
    bytes extraOptions; // Extra LayerZero options
    bytes composeMsg; // Compose message for OFT
    bytes oftCmd; // OFT command
}

/// @notice Messaging fee struct (same as LayerZero)
struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

/// @notice Messaging receipt struct
struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}
