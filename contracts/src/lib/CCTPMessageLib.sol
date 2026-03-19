// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Errors } from "./Errors.sol";

/// @title CCTPMessageLib
/// @author Aqua0 Team
/// @notice Library to extract hookData from a CCTP v2 message
/// @dev CCTP message layout:
///      Outer header (144 bytes): version[4] + sourceDomain[4] + destinationDomain[4] + nonce[32]
///        + sender[32] + recipient[32] + destinationCaller[32] + finalityThreshold[4]
///      BurnMessageV2 body (232 bytes fixed): version[4] + burnSource[4] + burnToken[32]
///        + mintRecipient[32] + amount[32] + messageSender[32] + maxFee[32] + feeExecuted[32]
///        + mintAmount[32]
///      hookData starts at byte 144 + 232 = 376
library CCTPMessageLib {
    uint256 internal constant OUTER_HEADER_SIZE = 144;
    uint256 internal constant BURN_MSG_FIXED_SIZE = 232;
    uint256 internal constant HOOK_DATA_OFFSET = 376; // 144 + 232

    /// @notice Extract hookData from a CCTP message
    /// @param message The full CCTP message bytes
    /// @return hookData The hookData portion of the message (everything after byte 376)
    function extractHookData(bytes calldata message) internal pure returns (bytes calldata hookData) {
        if (message.length < HOOK_DATA_OFFSET) revert Errors.CCTPMessageTooShort();
        return message[HOOK_DATA_OFFSET:];
    }
}
