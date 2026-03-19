// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IStargate, SendParam, MessagingFee, MessagingReceipt } from "../interface/IStargate.sol";
import { IWETH } from "../interface/IWETH.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";

/// @title StargateAdapter
/// @author Aqua0 Team
/// @notice Multi-asset adapter contract for cross-chain token bridging via Stargate V2
/// @dev Maps tokens to their corresponding Stargate pools. One deployment handles all tokens.
///      It can:
///      - bridge tokens directly to a recipient
///      - bridge tokens + attach a compose message for Composer on destination.
contract StargateAdapter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    /// @notice Mapping from token address to its Stargate pool
    mapping(address token => address pool) private _tokenToPool;

    /// @notice Array of registered token addresses
    address[] private _registeredTokens;

    /// @notice Constructor
    /// @param _owner The owner address
    constructor(address _owner) Ownable(_owner) { }

    /// @notice Register a Stargate pool for a token
    /// @param _token The token address
    /// @param _pool The Stargate pool address
    function registerPool(address _token, address _pool) external onlyOwner nonReentrant {
        if (_token == address(0)) revert Errors.ZeroAddress();
        if (_pool == address(0)) revert Errors.ZeroAddress();
        if (_tokenToPool[_token] != address(0)) revert Errors.PoolAlreadyRegistered();

        _tokenToPool[_token] = _pool;
        _registeredTokens.push(_token);
        emit Events.StargatePoolRegistered(_token, _pool);
    }

    /// @notice Remove a registered Stargate pool for a token
    /// @param _token The token address
    function removePool(address _token) external onlyOwner nonReentrant {
        if (_token == address(0)) revert Errors.ZeroAddress();
        address pool = _tokenToPool[_token];
        if (pool == address(0)) revert Errors.PoolNotRegistered();

        delete _tokenToPool[_token];

        // Remove from array
        uint256 len = _registeredTokens.length;
        for (uint256 i = 0; i < len; i++) {
            if (_registeredTokens[i] == _token) {
                _registeredTokens[i] = _registeredTokens[len - 1];
                _registeredTokens.pop();
                break;
            }
        }

        emit Events.StargatePoolRemoved(_token, pool);
    }

    /// @notice Get the Stargate pool address for a given token
    /// @param _token The token address
    /// @return The Stargate pool address
    function getPool(address _token) external view returns (address) {
        return _tokenToPool[_token];
    }

    /// @notice Get all registered token addresses
    /// @return The array of registered token addresses
    function getRegisteredTokens() external view returns (address[] memory) {
        return _registeredTokens;
    }

    /// @notice Quotes the fee for bridging tokens (simple send, no compose)
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _recipient The recipient address on destination chain
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive
    /// @return fee The native fee required
    function quoteBridgeFee(address _token, uint32 _dstEid, address _recipient, uint256 _amount, uint256 _minAmount)
        external
        view
        returns (uint256 fee)
    {
        IStargate stargate = _getStargate(_token);
        SendParam memory sendParam = _buildSendParam(_dstEid, _recipient, _amount, _minAmount, "", "");
        MessagingFee memory msgFee = stargate.quoteSend(sendParam, false);
        return msgFee.nativeFee;
    }

    /// @notice Quotes the fee for bridging tokens with compose (includes executor gas for lzCompose)
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _dstComposer The Composer address on destination chain
    /// @param _composeMsg The compose message payload
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive
    /// @param _lzReceiveGas Gas allocated for lzReceive on destination
    /// @param _lzComposeGas Gas allocated for lzCompose on destination
    /// @return fee The native fee required
    function quoteBridgeWithComposeFee(
        address _token,
        uint32 _dstEid,
        address _dstComposer,
        bytes calldata _composeMsg,
        uint256 _amount,
        uint256 _minAmount,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) external view returns (uint256 fee) {
        IStargate stargate = _getStargate(_token);
        bytes memory extraOptions = _buildLzComposeOptions(_lzReceiveGas, _lzComposeGas);
        SendParam memory sendParam =
            _buildSendParam(_dstEid, _dstComposer, _amount, _minAmount, _composeMsg, extraOptions);
        MessagingFee memory msgFee = stargate.quoteSend(sendParam, false);
        return msgFee.nativeFee;
    }

    /// @notice Bridges tokens to another chain via Stargate
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _recipient The recipient address on destination chain
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive (slippage protection)
    /// @return guid The message GUID for tracking
    function bridge(address _token, uint32 _dstEid, address _recipient, uint256 _amount, uint256 _minAmount)
        external
        payable
        nonReentrant
        returns (bytes32 guid)
    {
        if (_amount == 0) revert Errors.ZeroAmount();
        if (_recipient == address(0)) revert Errors.ZeroAddress();

        IStargate stargate = _getStargate(_token);
        bool isNativePool = stargate.token() == address(0);

        // Pull tokens from caller
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        if (isNativePool) {
            // Native ETH pool: unwrap WETH → ETH so the pool receives native ETH via msg.value.
            // nativeFee = msg.value - amount (the LZ messaging fee portion only).
            IWETH(_token).withdraw(_amount);
        } else {
            // ERC20 pool: approve pool to pull tokens via transferFrom
            IERC20(_token).forceApprove(address(stargate), _amount);
        }

        SendParam memory sendParam = _buildSendParam(_dstEid, _recipient, _amount, _minAmount, "", "");
        uint256 nativeFee = isNativePool ? msg.value - _amount : msg.value;
        MessagingFee memory fee = MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 });

        (MessagingReceipt memory receipt, uint256 amountOut) =
            stargate.send{ value: msg.value }(sendParam, fee, msg.sender);

        emit Events.TokensBridged(_dstEid, _recipient, _amount, amountOut, receipt.guid);
        return receipt.guid;
    }

    /// @notice Bridge tokens to a Composer with an attached compose message
    /// @dev Used for flows where the destination chain should credit a specific Account and
    ///      immediately call into Aqua via the vault's onCrosschainDeposit hook.
    ///      Builds TYPE_3 executor options with gas allocated for both lzReceive and lzCompose.
    /// @param _token The token to bridge
    /// @param _dstEid The destination endpoint ID
    /// @param _dstComposer The Composer contract on the destination chain
    /// @param _composeMsg ABI-encoded payload for the composer (e.g. account, strategyBytes, tokens, amounts)
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive on destination (slippage protection)
    /// @param _lzReceiveGas Gas allocated for lzReceive on destination executor
    /// @param _lzComposeGas Gas allocated for lzCompose on destination executor
    /// @return guid The message GUID for tracking
    function bridgeWithCompose(
        address _token,
        uint32 _dstEid,
        address _dstComposer,
        bytes calldata _composeMsg,
        uint256 _amount,
        uint256 _minAmount,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) external payable nonReentrant returns (bytes32 guid) {
        if (_amount == 0) revert Errors.ZeroAmount();
        if (_dstComposer == address(0)) revert Errors.ZeroAddress();
        if (_lzComposeGas == 0) revert Errors.InvalidInput();

        IStargate stargate = _getStargate(_token);
        bool isNativePool = stargate.token() == address(0);

        // Pull tokens from caller
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        if (isNativePool) {
            // Native ETH pool: unwrap WETH → ETH so the pool receives native ETH via msg.value.
            // nativeFee = msg.value - amount (the LZ messaging fee portion only).
            IWETH(_token).withdraw(_amount);
        } else {
            // ERC20 pool: approve pool to pull tokens via transferFrom
            IERC20(_token).forceApprove(address(stargate), _amount);
        }

        bytes memory extraOptions = _buildLzComposeOptions(_lzReceiveGas, _lzComposeGas);
        SendParam memory sendParam =
            _buildSendParam(_dstEid, _dstComposer, _amount, _minAmount, _composeMsg, extraOptions);
        uint256 nativeFee = isNativePool ? msg.value - _amount : msg.value;
        MessagingFee memory fee = MessagingFee({ nativeFee: nativeFee, lzTokenFee: 0 });

        (MessagingReceipt memory receipt, uint256 amountOut) =
            stargate.send{ value: msg.value }(sendParam, fee, msg.sender);

        emit Events.TokensBridged(_dstEid, _dstComposer, _amount, amountOut, receipt.guid);
        return receipt.guid;
    }

    /// @notice Resolve the Stargate pool for a token, reverting if not registered
    /// @param _token The token address
    /// @return stargate The Stargate pool interface
    function _getStargate(address _token) internal view returns (IStargate stargate) {
        address pool = _tokenToPool[_token];
        if (pool == address(0)) revert Errors.PoolNotRegistered();
        return IStargate(pool);
    }

    /// @notice Build LayerZero V2 TYPE_3 executor options with lzReceive + lzCompose gas
    /// @dev Uses the official LayerZero OptionsBuilder SDK
    /// @param _receiveGas Gas for lzReceive execution
    /// @param _composeGas Gas for lzCompose execution
    /// @return The encoded TYPE_3 executor options
    function _buildLzComposeOptions(uint128 _receiveGas, uint128 _composeGas) internal pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_receiveGas, 0)
            .addExecutorLzComposeOption(0, _composeGas, 0);
    }

    /// @notice Builds the SendParam struct for Stargate
    /// @param _dstEid The destination endpoint ID
    /// @param _recipient The recipient address on destination chain
    /// @param _amount The amount in local decimals
    /// @param _minAmount The minimum amount to receive
    /// @param _composeMsg The compose message (empty bytes for simple sends)
    /// @param _extraOptions Extra LayerZero executor options (empty bytes for simple sends)
    /// @return The constructed SendParam struct
    function _buildSendParam(
        uint32 _dstEid,
        address _recipient,
        uint256 _amount,
        uint256 _minAmount,
        bytes memory _composeMsg,
        bytes memory _extraOptions
    ) internal pure returns (SendParam memory) {
        return SendParam({
            dstEid: _dstEid,
            to: bytes32(uint256(uint160(_recipient))),
            amountLD: _amount,
            minAmountLD: _minAmount,
            extraOptions: _extraOptions,
            composeMsg: _composeMsg,
            oftCmd: ""
        });
    }

    /// @notice Allows the contract to receive ETH for fee refunds
    receive() external payable { }
}
