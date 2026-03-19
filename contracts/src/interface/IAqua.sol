// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IAqua
/// @author Aqua0 Team
/// @notice Interface for 1inch Aqua protocol (shared liquidity layer)
/// @dev This interface represents the subset of Aqua functionality used by Aqua0.
///      The actual Aqua contract is deployed at 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31
///
///      Key Aqua concepts:
///      - Virtual balances: _balances[maker][app][strategyHash][token]
///        - maker: msg.sender when calling ship() — the LP Smart Account address
///        - app: First parameter to ship() — the contract managing the strategy
///        - strategyHash: keccak256(strategy) — hash of the raw strategy bytes
///        - token: The token address
///
///      - Strategies are SwapVM bytecode programs, NOT separate contracts
///      - ship() creates virtual balance entries (maker = msg.sender, app = first param)
///      - dock() zeros virtual balance entries (maker = msg.sender, app = first param)
///      - pull()/push() handle token settlement during swaps
///
///      This interface covers the subset of Aqua functionality used by Aqua0.
interface IAqua {
    /// @notice Returns the raw balance for a specific maker, app, strategy, and token
    /// @param maker The maker address (LP Smart Account)
    /// @param app The app address that manages the strategy
    /// @param strategyHash The strategy hash (keccak256 of raw strategy bytes)
    /// @param token The token address
    /// @return balance The current balance amount
    /// @return tokensCount The number of tokens in the strategy (0xff = docked)
    function rawBalances(address maker, address app, bytes32 strategyHash, address token)
        external
        view
        returns (uint248 balance, uint8 tokensCount);

    /// @notice Returns balances of two tokens in a strategy, reverts if any token is not active
    /// @param maker The maker address (LP Smart Account)
    /// @param app The app address that manages the strategy
    /// @param strategyHash The strategy hash
    /// @param token0 The first token address
    /// @param token1 The second token address
    /// @return balance0 The balance for the first token
    /// @return balance1 The balance for the second token
    function safeBalances(address maker, address app, bytes32 strategyHash, address token0, address token1)
        external
        view
        returns (uint256 balance0, uint256 balance1);

    /// @notice Ship a new strategy and set initial balances
    /// @dev Creates virtual balance entries in Aqua's registry.
    ///      The caller (msg.sender) becomes the "maker" in the 4D mapping.
    ///      strategyHash = keccak256(strategy)
    ///      Emits Shipped(maker, app, strategyHash, strategy)
    /// @param app The app/implementation contract address
    /// @param strategy The strategy bytes (SwapVM bytecode program)
    /// @param tokens The tokens to allocate
    /// @param amounts The amounts to allocate for each token
    /// @return strategyHash The strategy hash (keccak256 of strategy bytes)
    function ship(address app, bytes memory strategy, address[] memory tokens, uint256[] memory amounts)
        external
        returns (bytes32 strategyHash);

    /// @notice Dock (deactivate) a strategy by clearing balances for specified tokens
    /// @dev Sets balances to 0 for all specified tokens, marks them as docked.
    ///      The caller (msg.sender) is the maker.
    ///      Emits Docked(maker, app, strategyHash)
    /// @param app The app address associated with the strategy
    /// @param strategyHash The strategy hash to dock
    /// @param tokens Array of token addresses to clear (must include all strategy tokens)
    function dock(address app, bytes32 strategyHash, address[] memory tokens) external;
}
