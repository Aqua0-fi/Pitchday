// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IBridgeRegistry
/// @author Aqua0 Team
/// @notice Interface for the BridgeRegistry contract
interface IBridgeRegistry {
    /// @notice Get the adapter address for a given key
    /// @param key The adapter key (e.g. keccak256("STARGATE"))
    /// @return The adapter address
    function getAdapter(bytes32 key) external view returns (address);

    /// @notice Check if an address is a trusted composer
    /// @param composer The address to check
    /// @return Whether the address is a trusted composer
    function isTrustedComposer(address composer) external view returns (bool);
}
