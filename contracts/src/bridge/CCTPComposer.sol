// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 as OZERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccount } from "../interface/IAccount.sol";
import { CCTPMessageLib } from "../lib/CCTPMessageLib.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";

/// @title IMessageTransmitterV2
/// @notice Minimal interface for Circle's MessageTransmitterV2
interface IMessageTransmitterV2 {
    /// @notice Receive a CCTP message and mint tokens
    /// @param message The CCTP message bytes
    /// @param attestation The Circle attestation signature
    /// @return success Whether the message was received successfully
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);
}

/// @title CCTPComposer
/// @author Aqua0 Team
/// @notice Destination-side receiver for CCTP v2 bridged tokens using the self-relay pattern
/// @dev Single atomic call: backend calls relayAndCompose(message, attestation, composePayload)
///      which mints USDC and executes compose in one tx. If anything fails, the whole tx reverts.
///      No orphaned USDC, no $0.20/transfer Forwarding Service fee.
///      Backend polls Circle Attestation API for attestation before calling.
contract CCTPComposer is Ownable, ReentrancyGuard {
    using SafeERC20 for OZERC20;

    /// @notice Circle's MessageTransmitterV2 address
    address public MESSAGE_TRANSMITTER;

    /// @notice The USDC token address on this chain
    address public TOKEN;

    /// @notice Constructor
    /// @param _messageTransmitter The MessageTransmitterV2 address
    /// @param _token The USDC token address
    /// @param _owner The owner address
    constructor(address _messageTransmitter, address _token, address _owner) Ownable(_owner) {
        if (_messageTransmitter == address(0)) revert Errors.ZeroAddress();
        if (_token == address(0)) revert Errors.ZeroAddress();
        MESSAGE_TRANSMITTER = _messageTransmitter;
        TOKEN = _token;
    }

    /// @notice Relay a CCTP message and execute compose in a single atomic transaction
    /// @dev Backend calls this after obtaining attestation from Circle's Attestation API.
    ///      MessageTransmitterV2 has built-in nonce replay protection — no need for ours.
    /// @param message The CCTP message bytes
    /// @param attestation The Circle attestation signature
    /// @param composePayload ABI-encoded payload: (address account, bytes strategyBytes, address[] tokens, uint256[] amounts)
    function relayAndCompose(bytes calldata message, bytes calldata attestation, bytes calldata composePayload)
        external
        nonReentrant
    {
        // Verify composePayload matches hookData in the attested message
        bytes calldata hookData = CCTPMessageLib.extractHookData(message);
        if (keccak256(hookData) != keccak256(composePayload)) revert Errors.HookDataMismatch();

        // Record balance before relay
        uint256 balanceBefore = OZERC20(TOKEN).balanceOf(address(this));

        // Relay the CCTP message — mints USDC to this contract
        bool success = IMessageTransmitterV2(MESSAGE_TRANSMITTER).receiveMessage(message, attestation);
        if (!success) revert Errors.CCTPRelayFailed();

        // Calculate amount received
        uint256 balanceAfter = OZERC20(TOKEN).balanceOf(address(this));
        uint256 amountReceived = balanceAfter - balanceBefore;

        // Handle compose — same pattern as Composer._handleCompose()
        bytes32 strategyHash = _handleCompose(OZERC20(TOKEN), amountReceived, composePayload);

        emit Events.CCTPComposeReceived(amountReceived, strategyHash);
    }

    /// @notice Internal handler for composed bridge deposits
    /// @param _token The bridged token
    /// @param amountReceived The amount of tokens received from the bridge
    /// @param composeMsg ABI-encoded payload: (address account, bytes strategyBytes, address[] tokens, uint256[] amounts)
    /// @return strategyHash The strategy hash returned by the account's Aqua ship
    function _handleCompose(OZERC20 _token, uint256 amountReceived, bytes memory composeMsg)
        internal
        returns (bytes32 strategyHash)
    {
        if (amountReceived == 0) revert Errors.ZeroAmount();
        if (composeMsg.length == 0) revert Errors.InvalidInput();

        (address account, bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts) =
            abi.decode(composeMsg, (address, bytes, address[], uint256[]));

        if (account == address(0)) revert Errors.ZeroAddress();
        if (strategyBytes.length == 0) revert Errors.InvalidStrategyBytes();
        if (tokens.length == 0 || tokens.length != amounts.length) revert Errors.InvalidInput();

        // Forward bridged tokens to the user's account
        _token.safeTransfer(account, amountReceived);

        // Inform the account of the cross-chain deposit so it can ship into Aqua
        strategyHash = IAccount(account).onCrosschainDeposit(strategyBytes, tokens, amounts);
    }

    /// @notice Update the MessageTransmitter address
    /// @param _messageTransmitter The new MessageTransmitter address
    function setMessageTransmitter(address _messageTransmitter) external onlyOwner {
        if (_messageTransmitter == address(0)) revert Errors.ZeroAddress();
        address oldTransmitter = MESSAGE_TRANSMITTER;
        MESSAGE_TRANSMITTER = _messageTransmitter;
        emit Events.MessageTransmitterSet(oldTransmitter, _messageTransmitter);
    }

    /// @notice Update the token address
    /// @param _token The new token address
    function setToken(address _token) external onlyOwner {
        if (_token == address(0)) revert Errors.ZeroAddress();
        address oldToken = TOKEN;
        TOKEN = _token;
        emit Events.CCTPComposerTokenSet(oldToken, _token);
    }
}
