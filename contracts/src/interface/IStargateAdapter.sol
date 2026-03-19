// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IStargateAdapter
/// @author Aqua0 Team
/// @notice Interface for the StargateAdapter bridge contract
interface IStargateAdapter {
    /// @notice Bridge tokens with an attached compose message for Composer on destination
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _dstComposer The Composer contract on the destination chain
    /// @param _composeMsg ABI-encoded payload for the composer
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive on destination (slippage protection)
    /// @param _lzReceiveGas Gas allocated for lzReceive on destination executor
    /// @param _lzComposeGas Gas allocated for lzCompose on destination executor
    /// @return guid The message GUID for tracking
    function bridgeWithCompose(
        address _token,
        uint32 _dstEid,
        address _dstComposer,
        bytes calldata _composeMsg,
        uint256 _amount,
        uint256 _minAmount,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) external payable returns (bytes32 guid);

    /// @notice Bridges tokens to another chain via Stargate (simple send, no compose)
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _recipient The recipient address on destination chain
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive (slippage protection)
    /// @return guid The message GUID for tracking
    function bridge(address _token, uint32 _dstEid, address _recipient, uint256 _amount, uint256 _minAmount)
        external
        payable
        returns (bytes32 guid);

    /// @notice Quotes the fee for bridging tokens (simple send, no compose)
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _recipient The recipient address on destination chain
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive
    /// @return fee The native fee required
    function quoteBridgeFee(address _token, uint32 _dstEid, address _recipient, uint256 _amount, uint256 _minAmount)
        external
        view
        returns (uint256 fee);

    /// @notice Quotes the fee for bridging tokens with compose
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _dstComposer The Composer address on destination chain
    /// @param _composeMsg The compose message payload
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive
    /// @param _lzReceiveGas Gas allocated for lzReceive on destination
    /// @param _lzComposeGas Gas allocated for lzCompose on destination
    /// @return fee The native fee required
    function quoteBridgeWithComposeFee(
        address _token,
        uint32 _dstEid,
        address _dstComposer,
        bytes calldata _composeMsg,
        uint256 _amount,
        uint256 _minAmount,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) external view returns (uint256 fee);

    /// @notice Gets the Stargate pool address for a given token
    /// @param _token The token address
    /// @return The Stargate pool address
    function getPool(address _token) external view returns (address);
}
