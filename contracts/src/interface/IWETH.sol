// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IWETH
/// @notice Minimal interface for Wrapped Ether (WETH9)
interface IWETH {
    /// @notice Unwrap WETH to native ETH
    /// @param amount The amount to unwrap
    function withdraw(uint256 amount) external;

    /// @notice Wrap native ETH to WETH
    function deposit() external payable;

    /// @notice Transfer WETH
    /// @param to The recipient address
    /// @param amount The amount to transfer
    /// @return success Whether the transfer succeeded
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Approve a spender
    /// @param spender The spender address
    /// @param amount The allowance amount
    /// @return success Whether the approval succeeded
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Get balance of an account
    /// @param account The account address
    /// @return The WETH balance
    function balanceOf(address account) external view returns (uint256);
}
