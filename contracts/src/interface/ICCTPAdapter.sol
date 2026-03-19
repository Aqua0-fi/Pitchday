// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title ICCTPAdapter
/// @author Aqua0 Team
/// @notice Interface for the CCTPAdapter bridge contract
interface ICCTPAdapter {
    /// @notice Bridge tokens via CCTP v2 with a hook payload for the destination composer
    /// @param token The token to bridge (USDC)
    /// @param amount The amount to bridge
    /// @param dstDomain The CCTP destination domain ID
    /// @param mintRecipient The recipient on the destination chain (CCTPComposer)
    /// @param hookData ABI-encoded hook payload for the destination
    /// @param maxFee The maximum fee for the CCTP transfer
    /// @param minFinalityThreshold The minimum finality threshold for fast transfer
    /// @return nonce The CCTP message nonce
    function bridgeWithHook(
        address token,
        uint256 amount,
        uint32 dstDomain,
        address mintRecipient,
        bytes calldata hookData,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external payable returns (uint64 nonce);
}
