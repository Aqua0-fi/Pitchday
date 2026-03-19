// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title ISwapVM
/// @notice Interface for 1inch SwapVM Router
interface ISwapVM {
    /// @notice Execute a SwapVM bytecode program
    /// @param program The bytecode program to execute
    /// @param input The input data for the program
    /// @return output The output data from execution
    function execute(bytes memory program, bytes memory input) external returns (bytes memory output);
}
