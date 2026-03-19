// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 as OZERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccount } from "../interface/IAccount.sol";
import { IWETH } from "../interface/IWETH.sol";
import { ILayerZeroComposer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";

/// @title Composer
/// @author Aqua0 Team
/// @notice Multi-asset destination-side bridge receiver for LP account deposits
/// @dev Implements LayerZero V2 ILayerZeroComposer to receive composed messages from the LZ executor.
///      Maps Stargate pool addresses to their bridged token addresses. One deployment handles all tokens.
///      The flow is:
///      1. LZ executor calls lzCompose() on this contract
///      2. lzCompose() validates caller (must be LZ_ENDPOINT) and _from (must be a registered pool)
///      3. Decodes the OFTComposeMsgCodec message to extract amountLD and app-level composeMsg
///      4. Delegates to _handleCompose() which forwards tokens to account and calls onCrosschainDeposit
contract Composer is ILayerZeroComposer, Ownable, ReentrancyGuard {
    using SafeERC20 for OZERC20;

    /// @notice LayerZero V2 endpoint address (the only allowed caller of lzCompose)
    address public LZ_ENDPOINT;

    /// @notice WETH address for native ETH wrapping
    /// @dev Stargate native ETH pools deliver raw ETH; this contract wraps it before forwarding.
    address public WETH;

    /// @notice Mapping from Stargate pool address to its bridged token
    mapping(address stargatePool => address token) private _poolToToken;

    /// @notice Array of registered Stargate pool addresses
    address[] private _registeredPools;

    /// @notice Constructor
    /// @param _lzEndpoint The LayerZero V2 endpoint address
    /// @param _owner Owner for admin operations
    constructor(address _lzEndpoint, address _owner) Ownable(_owner) {
        if (_lzEndpoint == address(0)) revert Errors.ZeroAddress();
        if (_owner == address(0)) revert Errors.ZeroAddress();

        LZ_ENDPOINT = _lzEndpoint;
    }

    /// @notice Register a Stargate pool and its bridged token
    /// @param _stargatePool The Stargate pool address
    /// @param _token The bridged token address for this pool
    function registerPool(address _stargatePool, address _token) external onlyOwner nonReentrant {
        if (_stargatePool == address(0)) revert Errors.ZeroAddress();
        if (_token == address(0)) revert Errors.ZeroAddress();
        if (_poolToToken[_stargatePool] != address(0)) revert Errors.PoolAlreadyRegistered();

        _poolToToken[_stargatePool] = _token;
        _registeredPools.push(_stargatePool);
        emit Events.ComposerPoolRegistered(_stargatePool, _token);
    }

    /// @notice Remove a registered Stargate pool
    /// @param _stargatePool The Stargate pool address
    function removePool(address _stargatePool) external onlyOwner nonReentrant {
        if (_stargatePool == address(0)) revert Errors.ZeroAddress();
        address tokenAddr = _poolToToken[_stargatePool];
        if (tokenAddr == address(0)) revert Errors.PoolNotRegistered();

        delete _poolToToken[_stargatePool];

        // Remove from array
        uint256 len = _registeredPools.length;
        for (uint256 i = 0; i < len; i++) {
            if (_registeredPools[i] == _stargatePool) {
                _registeredPools[i] = _registeredPools[len - 1];
                _registeredPools.pop();
                break;
            }
        }

        emit Events.ComposerPoolRemoved(_stargatePool, tokenAddr);
    }

    /// @notice Get the token address for a registered Stargate pool
    /// @param _stargatePool The Stargate pool address
    /// @return The token address
    function getToken(address _stargatePool) external view returns (address) {
        return _poolToToken[_stargatePool];
    }

    /// @notice Get all registered Stargate pool addresses
    /// @return The array of registered pool addresses
    function getRegisteredPools() external view returns (address[] memory) {
        return _registeredPools;
    }

    /// @notice Update the LayerZero V2 endpoint address
    /// @param _lzEndpoint The new endpoint address
    function setLzEndpoint(address _lzEndpoint) external onlyOwner nonReentrant {
        if (_lzEndpoint == address(0)) revert Errors.ZeroAddress();
        address oldEndpoint = LZ_ENDPOINT;
        LZ_ENDPOINT = _lzEndpoint;
        emit Events.LzEndpointSet(oldEndpoint, _lzEndpoint);
    }

    /// @notice Set the WETH address for native ETH wrapping
    /// @dev Stargate native ETH pools deliver raw ETH; setting WETH allows this contract
    ///      to wrap it before forwarding to LP accounts.
    /// @param _weth The WETH contract address
    function setWeth(address _weth) external onlyOwner nonReentrant {
        if (_weth == address(0)) revert Errors.ZeroAddress();
        address oldWeth = WETH;
        WETH = _weth;
        emit Events.ComposerWethSet(oldWeth, _weth);
    }

    /// @notice LayerZero V2 compose callback
    /// @dev Called by the LZ executor via the endpoint after Stargate delivers tokens.
    ///      Validates that msg.sender is the LZ endpoint and _from is a registered Stargate pool.
    /// @param _from The OFT/Stargate contract that sent the message
    /// @param _guid The LayerZero message GUID
    /// @param _message The OFTComposeMsgCodec-encoded message
    /// @param _executor The executor calling this (unused)
    /// @param _extraData Additional executor data (unused)
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable override nonReentrant {
        // Suppress unused parameter warnings
        (_executor, _extraData);

        if (msg.sender != LZ_ENDPOINT) revert Errors.NotAuthorized();

        // Look up token by pool address — reverts if pool is not registered
        address tokenAddr = _poolToToken[_from];
        if (tokenAddr == address(0)) revert Errors.PoolNotRegistered();

        // Decode OFT compose message (SDK uses calldata slicing directly)
        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);
        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(_message);

        bytes32 strategyHash = _handleCompose(OZERC20(tokenAddr), amountLD, composeMsg);

        emit Events.ComposeReceived(_guid, _from, amountLD, strategyHash);
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

        // Forward bridged tokens to the user's account.
        // Stargate native ETH pools deliver raw ETH — wrap to WETH before transferring.
        if (address(_token) == WETH && address(this).balance >= amountReceived) {
            IWETH(WETH).deposit{ value: amountReceived }();
        }
        _token.safeTransfer(account, amountReceived);

        // Inform the account of the cross-chain deposit so it can ship into Aqua
        strategyHash = IAccount(account).onCrosschainDeposit(strategyBytes, tokens, amounts);
    }

    /// @notice Accept ETH (for LZ executor gas refunds)
    receive() external payable { }
}
