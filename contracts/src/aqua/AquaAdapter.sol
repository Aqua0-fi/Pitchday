// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { IAqua } from "../interface/IAqua.sol";
import { Errors } from "../lib/Errors.sol";

/// @title AquaAdapter
/// @author Aqua0 Team
/// @notice Optional helper contract for Aqua protocol interactions
/// @dev LP Smart Accounts typically call Aqua directly. This adapter is provided for:
///      - Batching operations
///      - Adding protocol-level hooks/validations
///      - Future extensibility
///
///      NOTE: When this adapter calls Aqua, IT becomes the "maker" (msg.sender in Aqua).
///      The `app` parameter determines the app in Aqua's 4D mapping.
///      Virtual balances are: _balances[AquaAdapter][app][strategyHash][token]
///
///      For most use cases, LP Smart Accounts should call Aqua directly so they are
///      both maker AND app, simplifying the access control model.
contract AquaAdapter {
    /// @notice Aqua protocol address
    IAqua public immutable AQUA;

    /// @notice Constructor
    /// @param _aqua The Aqua protocol address
    constructor(address _aqua) {
        if (_aqua == address(0)) revert Errors.ZeroAddress();
        AQUA = IAqua(_aqua);
    }

    /// @notice Get the Aqua protocol address
    /// @return The Aqua address
    function aqua() external view returns (address) {
        return address(AQUA);
    }

    /// @notice Ship strategy via adapter (adapter becomes maker in Aqua)
    /// @dev WARNING: AquaAdapter becomes the "maker" (msg.sender in Aqua), not the caller.
    ///      The `app` parameter determines the app in Aqua's mapping.
    /// @param app The app contract address for the strategy
    /// @param strategyBytes The SwapVM bytecode program
    /// @param tokens The tokens to allocate
    /// @param amounts The amounts to allocate
    /// @return strategyHash The strategy hash (keccak256 of strategyBytes)
    function ship(address app, bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts)
        external
        returns (bytes32 strategyHash)
    {
        if (app == address(0)) revert Errors.ZeroAddress();
        if (strategyBytes.length == 0) revert Errors.InvalidStrategyBytes();
        if (tokens.length == 0 || tokens.length != amounts.length) revert Errors.InvalidInput();

        // Call Aqua's ship - AquaAdapter becomes the maker (msg.sender in Aqua)
        strategyHash = AQUA.ship(app, strategyBytes, tokens, amounts);
    }

    /// @notice Dock strategy via adapter
    /// @dev WARNING: Only works if this adapter was the original "maker" (msg.sender when shipped)
    /// @param app The app address associated with the strategy
    /// @param strategyHash The strategy hash to dock
    /// @param tokens The token addresses to clear
    function dock(address app, bytes32 strategyHash, address[] memory tokens) external {
        if (app == address(0)) revert Errors.ZeroAddress();
        if (strategyHash == bytes32(0)) revert Errors.InvalidStrategy();

        AQUA.dock(app, strategyHash, tokens);
    }

    /// @notice Get raw balance for a maker/app/strategy/token
    /// @param maker The maker address (who called ship on Aqua)
    /// @param app The app address
    /// @param strategyHash The strategy hash
    /// @param token The token address
    /// @return balance The raw balance amount
    /// @return tokensCount The number of tokens in the strategy
    function getRawBalance(address maker, address app, bytes32 strategyHash, address token)
        external
        view
        returns (uint248 balance, uint8 tokensCount)
    {
        return AQUA.rawBalances(maker, app, strategyHash, token);
    }
}
