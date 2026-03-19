// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { ISwapVMRouter } from "../../src/interface/ISwapVMRouter.sol";

/// @title SwapVMProgramHelper
/// @notice Helper library for building valid SwapVM Order structs in fork tests
/// @dev Encodes MakerTraits and program bytecode without importing the full swap-vm dependency tree.
///
///      MakerTraits layout (uint256):
///        bit 255: shouldUnwrapWeth
///        bit 254: useAquaInsteadOfSignature (required for Aqua orders)
///        bit 253: allowZeroAmountIn
///        bits 252-245: hook flags
///        bits 224-160: orderDataSlicesIndexes (4x uint16 packed as uint64)
///        bits 159-0: receiver address (0 = maker)
///
///      Order.data layout (no hooks):
///        Just the raw program bytecode (hooks are empty, all slice indices = 0)
///
///      Opcode indices (from deployed SwapVM Router's Opcodes._opcodes() dynamic array):
///      NOTE: The _opcodes() assembly trick shifts all static array indices by -1.
///        13 = _deadline (expiration control)
///        18 = _dynamicBalancesXD (dynamic balance loading)
///        22 = _xycSwapXD (basic XYC swap / constant product)
///        37 = _salt (adds salt for uniqueness)
///        38 = _flatFeeAmountInXD (flat fee on input)
///        44 = _peggedSwapGrowPriceRange2D (StableSwap / pegged swap)
///
///      Program format: sequence of [opcode_index, args_length, ...args]
library SwapVMProgramHelper {
    /// @dev USE_AQUA_INSTEAD_OF_SIGNATURE bit flag (bit 254)
    uint256 constant USE_AQUA_BIT = 1 << 254;

    /// @dev Opcode index for _xycSwapXD in the deployed SwapVM Router
    uint8 constant OPCODE_XYC_SWAP = 22;

    /// @dev Opcode index for _salt in the deployed SwapVM Router
    uint8 constant OPCODE_SALT = 37;

    /// @dev Opcode index for _deadline in the deployed SwapVM Router
    uint8 constant OPCODE_DEADLINE = 13;

    /// @dev Opcode index for _dynamicBalancesXD in the deployed SwapVM Router
    uint8 constant OPCODE_DYNAMIC_BALANCES = 18;

    /// @dev Opcode index for _flatFeeAmountInXD in the deployed SwapVM Router
    uint8 constant OPCODE_FLAT_FEE = 38;

    /// @dev Opcode index for _peggedSwapGrowPriceRange2D in the deployed SwapVM Router
    uint8 constant OPCODE_PEGGED_SWAP = 44;

    /// @notice Build a minimal SwapVM Order with just a XYC swap instruction
    /// @dev This is the simplest valid Aqua order. No hooks, no salt, no deadline.
    ///      traits = USE_AQUA_BIT | (orderDataSlicesIndexes=0 since no hooks) | receiver=0 (= maker)
    ///      data = program bytecode (just _xycSwapXD with no args)
    /// @param maker The maker address (LP vault)
    /// @return order A valid ISwapVMRouter.Order
    function buildMinimalOrder(address maker) internal pure returns (ISwapVMRouter.Order memory order) {
        // Program: just _xycSwapXD with 0 args
        bytes memory program = abi.encodePacked(
            OPCODE_XYC_SWAP, // opcode index
            uint8(0) // args length = 0
        );

        order = ISwapVMRouter.Order({
            maker: maker,
            traits: USE_AQUA_BIT, // all other bits 0: no hooks, no unwrap, receiver=maker
            data: program
        });
    }

    /// @notice Build an AMM SwapVM Order with XYC swap + salt for uniqueness
    /// @dev Salt prevents strategy hash collisions when shipping the same program
    ///      for different positions. The salt is encoded as uint64.
    /// @param maker The maker address (LP vault)
    /// @param salt A unique salt value
    /// @return order A valid ISwapVMRouter.Order
    function buildAMMOrder(address maker, uint64 salt) internal pure returns (ISwapVMRouter.Order memory order) {
        // Program: _xycSwapXD (no args) + _salt (8 bytes arg = uint64)
        bytes memory program = abi.encodePacked(
            OPCODE_XYC_SWAP,
            uint8(0), // args length for xycSwap = 0
            OPCODE_SALT,
            uint8(8), // args length for salt = 8 bytes (uint64)
            salt
        );

        order = ISwapVMRouter.Order({ maker: maker, traits: USE_AQUA_BIT, data: program });
    }

    /// @notice Build an AMM SwapVM Order with XYC swap + deadline + salt
    /// @param maker The maker address (LP vault)
    /// @param expiration The deadline timestamp (uint40)
    /// @param salt A unique salt value
    /// @return order A valid ISwapVMRouter.Order
    function buildAMMOrderWithDeadline(address maker, uint40 expiration, uint64 salt)
        internal
        pure
        returns (ISwapVMRouter.Order memory order)
    {
        // Program: _xycSwapXD + _deadline (5 bytes = uint40) + _salt (8 bytes = uint64)
        bytes memory program = abi.encodePacked(
            OPCODE_XYC_SWAP,
            uint8(0),
            OPCODE_DEADLINE,
            uint8(5), // args length for deadline = 5 bytes (uint40)
            expiration,
            OPCODE_SALT,
            uint8(8),
            salt
        );

        order = ISwapVMRouter.Order({ maker: maker, traits: USE_AQUA_BIT, data: program });
    }

    /// @notice Build a Constant Product (x*y=k) SwapVM program
    /// @dev Encodes: DynamicBalances(tokens, balances) + FlatFee(feeBps) + XYCSwap()
    ///      Binary format per instruction: [opcode, argsLength, ...args]
    /// @param token0 First token address
    /// @param token1 Second token address
    /// @param balance0 Initial balance for token0
    /// @param balance1 Initial balance for token1
    /// @param feeBps Fee in basis points (uint32, where 1e9 = 100%)
    /// @return program The encoded program bytes
    function buildConstantProductProgram(
        address token0,
        address token1,
        uint256 balance0,
        uint256 balance1,
        uint32 feeBps
    ) internal pure returns (bytes memory program) {
        // DynamicBalances args: [uint16(tokensCount), token0(20), token1(20), balance0(32), balance1(32)]
        // Total args = 2 + 20 + 20 + 32 + 32 = 106 bytes
        bytes memory balancesArgs = abi.encodePacked(uint16(2), token0, token1, balance0, balance1);

        // FlatFee args: [uint32(feeBps)]
        // Total args = 4 bytes
        bytes memory feeArgs = abi.encodePacked(feeBps);

        program = abi.encodePacked(
            OPCODE_DYNAMIC_BALANCES,
            uint8(106), // args length for 2-token balances
            balancesArgs,
            OPCODE_FLAT_FEE,
            uint8(4), // args length for fee
            feeArgs,
            OPCODE_XYC_SWAP,
            uint8(0) // no args for xycSwap
        );
    }

    /// @notice Build a StableSwap (PeggedSwap) SwapVM program
    /// @dev Encodes: DynamicBalances(tokens, balances) + FlatFee(feeBps) + PeggedSwap(x0, y0, A, rateLt, rateGt)
    ///      Tokens are sorted by address (PeggedSwap requires tokenLt < tokenGt).
    ///      x0 = balanceLt * rateLt, y0 = balanceGt * rateGt (normalized reserves).
    /// @param token0 First token address
    /// @param token1 Second token address
    /// @param balance0 Initial balance for token0
    /// @param balance1 Initial balance for token1
    /// @param linearWidth The A parameter (scaled by 1e27; e.g. 0.8e27 for stablecoins)
    /// @param rate0 Rate multiplier for token0 (for decimal normalization)
    /// @param rate1 Rate multiplier for token1 (for decimal normalization)
    /// @param feeBps Fee in basis points (uint32, where 1e9 = 100%)
    /// @return program The encoded program bytes
    function buildStableSwapProgram(
        address token0,
        address token1,
        uint256 balance0,
        uint256 balance1,
        uint256 linearWidth,
        uint256 rate0,
        uint256 rate1,
        uint32 feeBps
    ) internal pure returns (bytes memory program) {
        // Sort tokens by address (PeggedSwap requires it)
        address tokenLt;
        address tokenGt;
        uint256 balanceLt;
        uint256 balanceGt;
        uint256 rateLt;
        uint256 rateGt;

        if (token0 < token1) {
            tokenLt = token0;
            tokenGt = token1;
            balanceLt = balance0;
            balanceGt = balance1;
            rateLt = rate0;
            rateGt = rate1;
        } else {
            tokenLt = token1;
            tokenGt = token0;
            balanceLt = balance1;
            balanceGt = balance0;
            rateLt = rate1;
            rateGt = rate0;
        }

        // Normalized initial reserves
        uint256 x0 = balanceLt * rateLt;
        uint256 y0 = balanceGt * rateGt;

        // DynamicBalances args (sorted order)
        bytes memory balancesArgs = abi.encodePacked(uint16(2), tokenLt, tokenGt, balanceLt, balanceGt);

        // FlatFee args
        bytes memory feeArgs = abi.encodePacked(feeBps);

        // PeggedSwap args: [x0(32), y0(32), linearWidth(32), rateLt(32), rateGt(32)] = 160 bytes
        bytes memory peggedArgs = abi.encodePacked(x0, y0, linearWidth, rateLt, rateGt);

        program = abi.encodePacked(
            OPCODE_DYNAMIC_BALANCES,
            uint8(106), // args length for 2-token balances
            balancesArgs,
            OPCODE_FLAT_FEE,
            uint8(4), // args length for fee
            feeArgs,
            OPCODE_PEGGED_SWAP,
            uint8(160), // args length for pegged swap (5 x 32 bytes)
            peggedArgs
        );
    }

    /// @notice Build an Aqua Order from a maker and raw program bytes
    /// @param maker The maker address (LP vault)
    /// @param program The SwapVM program bytecode
    /// @return order A valid ISwapVMRouter.Order with USE_AQUA_BIT set
    function buildAquaOrder(address maker, bytes memory program)
        internal
        pure
        returns (ISwapVMRouter.Order memory order)
    {
        order = ISwapVMRouter.Order({ maker: maker, traits: USE_AQUA_BIT, data: program });
    }

    /// @notice Build minimal taker data for Aqua swaps
    /// @dev Taker data layout: [uint160(threshold) | uint16(flags)]
    ///      Flags: isExactIn (0x0001) + useTransferFromAndAquaPush (0x0040) = 0x0041
    ///      All slice indices = 0 → no threshold check, to=msg.sender, no deadline, no hooks, no signature
    /// @return takerData The encoded taker data (22 bytes)
    function buildAquaTakerData() internal pure returns (bytes memory takerData) {
        takerData = abi.encodePacked(uint160(0), uint16(0x0041));
    }

    /// @notice Encode strategy bytes from an Order (for shipping to Aqua)
    /// @dev In real Aqua, strategyHash = keccak256(strategy).
    ///      For SwapVM orders, the strategy bytes are abi.encode(order).
    /// @param order The SwapVM Order
    /// @return The encoded strategy bytes
    function encodeStrategy(ISwapVMRouter.Order memory order) internal pure returns (bytes memory) {
        return abi.encode(order);
    }

    /// @notice Compute strategy hash from strategy bytes
    /// @dev Matches real Aqua: strategyHash = keccak256(strategy)
    /// @param strategyBytes The raw strategy bytes
    /// @return The strategy hash
    function computeStrategyHash(bytes memory strategyBytes) internal pure returns (bytes32) {
        return keccak256(strategyBytes);
    }

    /// @notice Encode a single SwapVM instruction
    /// @param opcode The opcode index
    /// @param args The instruction arguments
    /// @return The encoded instruction bytes [opcode, argsLen, ...args]
    function encodeInstruction(uint8 opcode, bytes memory args) internal pure returns (bytes memory) {
        return abi.encodePacked(opcode, uint8(args.length), args);
    }
}
