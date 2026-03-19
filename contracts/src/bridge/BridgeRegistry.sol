// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IBridgeRegistry } from "../interface/IBridgeRegistry.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";

/// @title BridgeRegistry
/// @author Aqua0 Team
/// @notice Generic key-value adapter registry + trusted composer set
/// @dev Deployed once per chain. All Accounts read from it via an immutable in the implementation bytecode.
///      Uses bytes32 keys for adapters so new bridge protocols can be added without redeployment.
contract BridgeRegistry is IBridgeRegistry, Ownable {
    /// @notice Mapping from adapter key to adapter address
    mapping(bytes32 => address) private _adapters;

    /// @notice Mapping of trusted composer addresses
    mapping(address => bool) private _trustedComposers;

    /// @notice Constructor
    /// @param _owner The owner address
    constructor(address _owner) Ownable(_owner) { }

    /// @notice Set an adapter for a given key
    /// @param key The adapter key (e.g. keccak256("STARGATE"))
    /// @param adapter The adapter address
    function setAdapter(bytes32 key, address adapter) external onlyOwner {
        if (adapter == address(0)) revert Errors.ZeroAddress();
        _adapters[key] = adapter;
        emit Events.AdapterSet(key, adapter);
    }

    /// @notice Remove an adapter for a given key
    /// @param key The adapter key
    function removeAdapter(bytes32 key) external onlyOwner {
        address oldAdapter = _adapters[key];
        if (oldAdapter == address(0)) revert Errors.AdapterNotRegistered();
        delete _adapters[key];
        emit Events.AdapterRemoved(key, oldAdapter);
    }

    /// @notice Get the adapter address for a given key
    /// @param key The adapter key
    /// @return The adapter address
    function getAdapter(bytes32 key) external view override returns (address) {
        return _adapters[key];
    }

    /// @notice Add a trusted composer
    /// @param composer The composer address to trust
    function addComposer(address composer) external onlyOwner {
        if (composer == address(0)) revert Errors.ZeroAddress();
        if (_trustedComposers[composer]) revert Errors.ComposerAlreadyTrusted();
        _trustedComposers[composer] = true;
        emit Events.ComposerAdded(composer);
    }

    /// @notice Remove a trusted composer
    /// @param composer The composer address to remove
    function removeComposer(address composer) external onlyOwner {
        if (!_trustedComposers[composer]) revert Errors.ComposerNotTrusted();
        _trustedComposers[composer] = false;
        emit Events.ComposerRemoved(composer);
    }

    /// @notice Check if an address is a trusted composer
    /// @param composer The address to check
    /// @return Whether the address is a trusted composer
    function isTrustedComposer(address composer) external view override returns (bool) {
        return _trustedComposers[composer];
    }
}
