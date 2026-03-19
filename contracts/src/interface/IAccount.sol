// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IAccount
/// @author Aqua0 Team
/// @notice Minimal interface for Account cross-chain hooks and bridge operations
interface IAccount {
    /// @notice Handle a cross-chain deposit that has already been transferred into the account
    /// @param strategyBytes The SwapVM bytecode program
    /// @param tokens The tokens to allocate
    /// @param amounts The amounts to allocate
    /// @return strategyHash The strategy hash returned by Aqua
    function onCrosschainDeposit(bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts)
        external
        returns (bytes32 strategyHash);

    /// @notice Bridge tokens cross-chain via Stargate/LayerZero with compose message
    /// @param _dstEid Destination LayerZero endpoint ID
    /// @param _dstComposer The Composer address on the destination chain
    /// @param _composeMsg ABI-encoded compose payload for the destination Composer
    /// @param _token The token to bridge
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive (slippage protection)
    /// @param _lzReceiveGas Gas allocated for lzReceive on destination
    /// @param _lzComposeGas Gas allocated for lzCompose on destination
    /// @return guid The LayerZero message GUID for tracking
    function bridgeStargate(
        uint32 _dstEid,
        address _dstComposer,
        bytes calldata _composeMsg,
        address _token,
        uint256 _amount,
        uint256 _minAmount,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) external payable returns (bytes32 guid);

    /// @notice Bridge tokens cross-chain via CCTP v2
    /// @param dstDomain The CCTP destination domain ID
    /// @param dstComposer The CCTPComposer address on the destination chain
    /// @param hookData ABI-encoded hook payload for the destination CCTPComposer
    /// @param token The token to bridge (USDC)
    /// @param amount The amount to bridge
    /// @param maxFee The maximum fee for the CCTP transfer
    /// @param minFinalityThreshold The minimum finality threshold for fast transfer
    /// @return nonce The CCTP message nonce
    function bridgeCCTP(
        uint32 dstDomain,
        address dstComposer,
        bytes calldata hookData,
        address token,
        uint256 amount,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external payable returns (uint64 nonce);
}
