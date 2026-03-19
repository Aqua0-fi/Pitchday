// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title ISwapVMRouter
/// @author Aqua0 Team
/// @notice Interface for the deployed 1inch SwapVM Router (quote/swap with Order).
/// @dev SwapVM is at 0x8fdd04dbf6111437b44bbca99c28882434e0958f on Base, Unichain, etc.
///      For Aqua-backed orders: set traits with useAquaInsteadOfSignature (bit 254).
///      Order.data with no hooks = just the SwapVM program bytes.
interface ISwapVMRouter {
    struct Order {
        address maker;
        uint256 traits; // MakerTraits: useAquaInsteadOfSignature = 1 << 254, receiver in low 160 bits
        bytes data; // For no hooks: the SwapVM program only
    }

    /// @notice Compute the hash of an order
    /// @dev For Aqua orders, hash = keccak256(abi.encode(order)); use same when shipping to Aqua.
    /// @param order The order to hash
    /// @return The order hash
    function hash(Order calldata order) external view returns (bytes32);

    /// @notice Quote the result of a swap without executing it
    /// @param order The maker order containing the SwapVM program
    /// @param tokenIn The input token address
    /// @param tokenOut The output token address
    /// @param amount The input amount
    /// @param takerTraitsAndData Taker traits and optional extra data
    /// @return amountIn The actual input amount
    /// @return amountOut The expected output amount
    /// @return orderHash The order hash
    function quote(
        Order calldata order,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes calldata takerTraitsAndData
    ) external view returns (uint256 amountIn, uint256 amountOut, bytes32 orderHash);

    /// @notice Execute a swap against a maker order
    /// @param order The maker order containing the SwapVM program
    /// @param tokenIn The input token address
    /// @param tokenOut The output token address
    /// @param amount The input amount
    /// @param takerTraitsAndData Taker traits and optional extra data
    /// @return amountIn The actual input amount consumed
    /// @return amountOut The output amount received
    /// @return orderHash The order hash
    function swap(
        Order calldata order,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bytes calldata takerTraitsAndData
    ) external returns (uint256 amountIn, uint256 amountOut, bytes32 orderHash);
}
