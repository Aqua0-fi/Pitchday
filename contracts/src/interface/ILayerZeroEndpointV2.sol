// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title ILayerZeroEndpointV2
/// @notice Minimal interface for LayerZero V2 endpoint
/// @dev Based on LayerZero V2 specification - https://docs.layerzero.network/v2
interface ILayerZeroEndpointV2 {
    /// @notice Sends a message to a destination chain
    /// @param _dstEid The destination endpoint ID
    /// @param _message The message bytes to send
    /// @param _options Additional options for the message
    /// @param _fee The messaging fee to pay
    /// @param _refundAddress The address to refund excess fees
    /// @return receipt The message receipt containing guid
    function send(
        uint32 _dstEid,
        bytes calldata _message,
        bytes calldata _options,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt);

    /// @notice Quotes the fee for sending a message
    /// @param _dstEid The destination endpoint ID
    /// @param _message The message bytes to quote
    /// @param _options Additional options for the message
    /// @param _payInLzToken Whether to pay in LZ token
    /// @return fee The quoted messaging fee
    function quote(uint32 _dstEid, bytes calldata _message, bytes calldata _options, bool _payInLzToken)
        external
        view
        returns (MessagingFee memory fee);

    /// @notice Sets the delegate for this sender
    /// @param _delegate The delegate address
    function setDelegate(address _delegate) external;
}

/// @notice Struct for messaging fee
struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

/// @notice Struct for messaging receipt
struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}
