// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICCTPAdapter } from "../interface/ICCTPAdapter.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";

/// @title ITokenMessengerV2
/// @notice Minimal interface for Circle's TokenMessengerV2
interface ITokenMessengerV2 {
    /// @notice Deposit tokens for burn with a hook on the destination chain
    /// @param amount The amount to burn
    /// @param destinationDomain The CCTP destination domain
    /// @param mintRecipient The recipient on destination (bytes32-encoded address)
    /// @param burnToken The token to burn
    /// @param destinationCaller Restricts who can relay on destination (bytes32(0) = anyone)
    /// @param maxBurnAmountFee Maximum fee deducted from burn amount
    /// @param minFinalityThreshold Minimum finality for fast transfer
    /// @param hookData Data passed to the hook on destination
    /// @return nonce The message nonce
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxBurnAmountFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external returns (uint64 nonce);
}

/// @title CCTPAdapter
/// @author Aqua0 Team
/// @notice Source-chain adapter wrapping Circle's TokenMessengerV2.depositForBurnWithHook()
/// @dev Same pull-pattern as StargateAdapter — caller approves tokens, adapter pulls and burns.
contract CCTPAdapter is ICCTPAdapter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Circle's TokenMessengerV2 address
    address public TOKEN_MESSENGER;

    /// @notice Constructor
    /// @param _tokenMessenger The TokenMessengerV2 address
    /// @param _owner The owner address
    constructor(address _tokenMessenger, address _owner) Ownable(_owner) {
        if (_tokenMessenger == address(0)) revert Errors.ZeroAddress();
        TOKEN_MESSENGER = _tokenMessenger;
    }

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
    ) external payable override nonReentrant returns (uint64 nonce) {
        if (amount == 0) revert Errors.ZeroAmount();
        if (token == address(0)) revert Errors.ZeroAddress();
        if (mintRecipient == address(0)) revert Errors.ZeroAddress();

        // Pull tokens from caller
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Approve TokenMessenger to burn
        IERC20(token).forceApprove(TOKEN_MESSENGER, amount);

        // Call depositForBurnWithHook via low-level call because the deployed
        // TokenMessengerV2 proxy may not return data (implementation ends with STOP opcode).
        // A high-level call would revert when ABI-decoding empty return data as uint64.
        (bool success, bytes memory returnData) = TOKEN_MESSENGER.call(
            abi.encodeCall(
                ITokenMessengerV2.depositForBurnWithHook,
                (
                    amount,
                    dstDomain,
                    bytes32(uint256(uint160(mintRecipient))),
                    token,
                    bytes32(uint256(uint160(mintRecipient))), // destinationCaller = CCTPComposer only
                    maxFee,
                    minFinalityThreshold,
                    hookData
                )
            )
        );
        if (!success) revert Errors.CCTPBurnFailed();

        // Decode nonce if return data is available; otherwise default to 0
        nonce = returnData.length >= 32 ? abi.decode(returnData, (uint64)) : 0;

        emit Events.CCTPBridged(dstDomain, mintRecipient, token, amount, nonce);
    }

    /// @notice Update the TokenMessenger address
    /// @param _tokenMessenger The new TokenMessenger address
    function setTokenMessenger(address _tokenMessenger) external onlyOwner {
        if (_tokenMessenger == address(0)) revert Errors.ZeroAddress();
        address oldMessenger = TOKEN_MESSENGER;
        TOKEN_MESSENGER = _tokenMessenger;
        emit Events.TokenMessengerSet(oldMessenger, _tokenMessenger);
    }
}
