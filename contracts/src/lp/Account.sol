// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20 as OZERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAqua } from "../interface/IAqua.sol";
import { IBridgeRegistry } from "../interface/IBridgeRegistry.sol";
import { IStargateAdapter } from "../interface/IStargateAdapter.sol";
import { ICCTPAdapter } from "../interface/ICCTPAdapter.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";

/// @title Account
/// @author Aqua0 Team
/// @notice Non-custodial LP account that holds tokens and acts as "maker" in Aqua's registry
/// @dev This is the maker address in Aqua's 4D mapping: _balances[maker][app][strategyHash][token]
///      The account ships under the SwapVM Router's app namespace so that the router can query
///      balances during swaps: _balances[account][swapVMRouter][strategyHash][token].
///      Deployed as a BeaconProxy — all instances share the same implementation via UpgradeableBeacon.
///      Bridge config is read from BridgeRegistry via an immutable reference.
contract Account is Initializable, Ownable, ReentrancyGuard {
    using SafeERC20 for OZERC20;

    /// @notice Adapter key for Stargate/LayerZero bridge
    bytes32 public constant STARGATE_KEY = keccak256("STARGATE");

    /// @notice Adapter key for CCTP bridge
    bytes32 public constant CCTP_KEY = keccak256("CCTP");

    /// @notice BridgeRegistry address — baked into implementation bytecode
    address public immutable BRIDGE_REGISTRY;

    /// @notice Factory address
    address private _factory;

    /// @notice Aqua protocol address (for ship/dock)
    IAqua private _aqua;

    /// @notice SwapVM Router address — used as "app" in Aqua's 4D mapping
    /// @dev The router queries Aqua with app = address(this) (the router), so the account must
    ///      ship under the same app namespace for balances to be visible during swaps.
    ///      Admin-settable to support router upgrades without account redeployment.
    address public swapVMRouter;

    /// @notice Authorized rebalancer address
    address public rebalancer;

    /// @notice Whether rebalancer is authorized
    bool public rebalancerAuthorized;

    /// @notice Stored tokens per strategy for dock() calls
    /// @dev dock() requires the token array; we store it at ship-time so dock() callers don't need it
    mapping(bytes32 => address[]) private _strategyTokens;

    /// @notice Storage gap for future upgrades
    uint256[44] private __gap;

    /// @notice Modifier to restrict access to owner or authorized rebalancer
    modifier onlyOwnerOrRebalancer() {
        if (msg.sender != owner() && !(msg.sender == rebalancer && rebalancerAuthorized)) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    /// @notice Restrict function access to trusted composers registered in BridgeRegistry
    modifier onlyComposer() {
        if (!IBridgeRegistry(BRIDGE_REGISTRY).isTrustedComposer(msg.sender)) {
            revert Errors.NotAuthorized();
        }
        _;
    }

    /// @notice Constructor — disables initializers on the implementation contract
    /// @dev The implementation is never used directly; proxies call initialize() instead.
    /// @param _bridgeRegistry The BridgeRegistry address (baked into implementation bytecode)
    constructor(address _bridgeRegistry) Ownable(address(1)) {
        BRIDGE_REGISTRY = _bridgeRegistry;
        _disableInitializers();
    }

    /// @notice Initialize the account (called once per proxy deployment)
    /// @param _owner The owner (LP's EOA or smart account)
    /// @param factory_ The factory address
    /// @param aqua_ The Aqua protocol address
    /// @param _swapVMRouter The SwapVM Router address (used as app in Aqua's 4D mapping)
    function initialize(address _owner, address factory_, address aqua_, address _swapVMRouter) external initializer {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        if (factory_ == address(0)) revert Errors.ZeroAddress();
        if (aqua_ == address(0)) revert Errors.ZeroAddress();
        if (_swapVMRouter == address(0)) revert Errors.ZeroAddress();

        _transferOwnership(_owner);
        _factory = factory_;
        _aqua = IAqua(aqua_);
        swapVMRouter = _swapVMRouter;
    }

    /// @notice Receive ETH (for gas sponsorship or native token operations)
    receive() external payable { }

    /// @notice Get the factory address
    /// @return The factory address
    function FACTORY() external view returns (address) {
        return _factory;
    }

    /// @notice Get the Aqua protocol address
    /// @return The Aqua protocol interface
    function AQUA() external view returns (IAqua) {
        return _aqua;
    }

    /// @notice Set the SwapVM Router address
    /// @dev The router address is used as "app" in Aqua's 4D mapping. Updating this allows
    ///      the account to work with upgraded router deployments without redeployment.
    /// @param _swapVMRouter The new SwapVM Router address
    function setSwapVMRouter(address _swapVMRouter) external onlyOwner nonReentrant {
        if (_swapVMRouter == address(0)) revert Errors.ZeroAddress();
        address oldRouter = swapVMRouter;
        swapVMRouter = _swapVMRouter;
        emit Events.SwapVMRouterSet(oldRouter, _swapVMRouter);
    }

    /// @notice Approve Aqua to spend tokens from this account
    /// @dev Must be called before ship() for the tokens to be pulled during swaps
    /// @param token The token to approve
    /// @param amount The amount to approve (use type(uint256).max for unlimited)
    function approveAqua(address token, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0)) revert Errors.ZeroAddress();
        // Use forceApprove to safely set allowance even for non-standard tokens
        OZERC20(token).forceApprove(address(_aqua), amount);
    }

    /// @notice Ship strategy to activate virtual balance in Aqua
    /// @dev Creates virtual balance entries in Aqua's registry.
    ///      maker = address(this) (msg.sender), app = swapVMRouter so the router can find balances.
    ///      Tokens must be in this account and approved for Aqua before calling.
    ///      strategyHash = keccak256(strategyBytes)
    /// @param strategyBytes The SwapVM bytecode program
    /// @param tokens The tokens to allocate
    /// @param amounts The amounts to allocate for each token
    /// @return strategyHash The strategy hash returned by Aqua
    function ship(bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts)
        external
        onlyOwner
        nonReentrant
        returns (bytes32 strategyHash)
    {
        if (strategyBytes.length == 0) revert Errors.InvalidStrategyBytes();
        if (tokens.length == 0) revert Errors.InvalidInput();
        if (tokens.length != amounts.length) revert Errors.InvalidInput();

        // Call Aqua's ship function - this creates virtual balances
        // maker = address(this) via msg.sender, app = swapVMRouter via first param
        strategyHash = _aqua.ship(swapVMRouter, strategyBytes, tokens, amounts);

        // Store tokens for later dock() calls
        _strategyTokens[strategyHash] = tokens;
    }

    /// @notice Handle a cross-chain deposit into this account and activate liquidity in Aqua
    /// @dev Called by a trusted composer (registered in BridgeRegistry) after it has:
    ///      1) received bridged tokens, and
    ///      2) transferred those tokens to this account.
    ///      This function does not move tokens; it only updates Aqua's virtual balances so that
    ///      this account remains the maker on the destination chain.
    /// @param strategyBytes The SwapVM bytecode program
    /// @param tokens The tokens to allocate
    /// @param amounts The amounts to allocate for each token
    /// @return strategyHash The strategy hash returned by Aqua
    function onCrosschainDeposit(bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts)
        external
        onlyComposer
        nonReentrant
        returns (bytes32 strategyHash)
    {
        if (strategyBytes.length == 0) revert Errors.InvalidStrategyBytes();
        if (tokens.length == 0) revert Errors.InvalidInput();
        if (tokens.length != amounts.length) revert Errors.InvalidInput();

        // Reuse existing ship logic to create virtual balances in Aqua.
        // maker = address(this) via msg.sender, app = swapVMRouter via first param
        strategyHash = _aqua.ship(swapVMRouter, strategyBytes, tokens, amounts);

        // Store tokens for later dock() calls
        _strategyTokens[strategyHash] = tokens;
    }

    /// @notice Dock strategy to deactivate virtual balance in Aqua
    /// @dev Zeros virtual balance entries in Aqua's registry.
    ///      Tokens remain in this account until explicit withdrawal.
    ///      Uses stored tokens from ship() — no need for caller to supply them.
    /// @param strategyHash The strategy hash to dock
    function dock(bytes32 strategyHash) external onlyOwnerOrRebalancer nonReentrant {
        if (strategyHash == bytes32(0)) revert Errors.InvalidStrategy();

        address[] memory storedTokens = _strategyTokens[strategyHash];
        if (storedTokens.length == 0) revert Errors.StrategyTokensNotFound();

        // maker = address(this) via msg.sender, app = swapVMRouter via first param
        _aqua.dock(swapVMRouter, strategyHash, storedTokens);
    }

    /// @notice Bridge tokens cross-chain via Stargate/LayerZero with compose message
    /// @dev Callable by owner or authorized rebalancer. Reads adapter from BridgeRegistry,
    ///      approves tokens to the adapter, then calls bridgeWithCompose to initiate the cross-chain transfer.
    /// @param _dstEid Destination LayerZero endpoint ID
    /// @param _dstComposer The Composer address on the destination chain
    /// @param _composeMsg ABI-encoded compose payload for the destination Composer
    /// @param _token The token to bridge
    /// @param _amount The amount to bridge
    /// @param _minAmount The minimum amount to receive (slippage protection)
    /// @param _lzReceiveGas Gas allocated for lzReceive on destination
    /// @param _lzComposeGas Gas allocated for lzCompose on destination
    /// @return guid The LayerZero message GUID for tracking
    function bridgeStargate(
        uint32 _dstEid,
        address _dstComposer,
        bytes calldata _composeMsg,
        address _token,
        uint256 _amount,
        uint256 _minAmount,
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) external payable onlyOwnerOrRebalancer nonReentrant returns (bytes32 guid) {
        address adapter = IBridgeRegistry(BRIDGE_REGISTRY).getAdapter(STARGATE_KEY);
        if (adapter == address(0)) revert Errors.ZeroAddress();
        if (_token == address(0)) revert Errors.ZeroAddress();
        if (_amount == 0) revert Errors.ZeroAmount();

        OZERC20(_token).forceApprove(adapter, _amount);
        guid = IStargateAdapter(adapter).bridgeWithCompose{ value: msg.value }(
            _token, _dstEid, _dstComposer, _composeMsg, _amount, _minAmount, _lzReceiveGas, _lzComposeGas
        );
    }

    /// @notice Bridge tokens cross-chain via CCTP v2
    /// @dev Callable by owner or authorized rebalancer. Reads adapter from BridgeRegistry,
    ///      approves tokens to the adapter, then calls bridgeWithHook to initiate the CCTP transfer.
    /// @param dstDomain The CCTP destination domain ID
    /// @param dstComposer The CCTPComposer address on the destination chain
    /// @param hookData ABI-encoded hook payload for the destination CCTPComposer
    /// @param token The token to bridge (USDC)
    /// @param amount The amount to bridge
    /// @param maxFee The maximum fee for the CCTP transfer
    /// @param minFinalityThreshold The minimum finality threshold for fast transfer
    /// @return nonce The CCTP message nonce
    function bridgeCCTP(
        uint32 dstDomain,
        address dstComposer,
        bytes calldata hookData,
        address token,
        uint256 amount,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external payable onlyOwnerOrRebalancer nonReentrant returns (uint64 nonce) {
        address adapter = IBridgeRegistry(BRIDGE_REGISTRY).getAdapter(CCTP_KEY);
        if (adapter == address(0)) revert Errors.ZeroAddress();

        OZERC20(token).forceApprove(adapter, amount);
        nonce = ICCTPAdapter(adapter).bridgeWithHook{ value: msg.value }(
            token, amount, dstDomain, dstComposer, hookData, maxFee, minFinalityThreshold
        );
    }

    /// @notice Withdraw tokens from this account (owner only)
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    function withdraw(address token, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();

        OZERC20(token).safeTransfer(owner(), amount);
        emit Events.Withdrawn(address(this), token, amount, owner());
    }

    /// @notice Withdraw ETH from this account (owner only)
    /// @param amount The amount to withdraw
    function withdrawETH(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();
        if (address(this).balance < amount) revert Errors.InsufficientBalance();

        (bool success,) = owner().call{ value: amount }("");
        if (!success) revert Errors.TransferFailed();
    }

    /// @notice Authorize rebalancer to trigger dock operations
    /// @param _rebalancer The rebalancer address
    function authorizeRebalancer(address _rebalancer) external onlyOwner nonReentrant {
        if (_rebalancer == address(0)) revert Errors.ZeroAddress();
        rebalancer = _rebalancer;
        rebalancerAuthorized = true;
        emit Events.RebalancerAuthorized(address(this), _rebalancer);
    }

    /// @notice Revoke rebalancer authorization
    function revokeRebalancer() external onlyOwner nonReentrant {
        rebalancerAuthorized = false;
        emit Events.RebalancerRevoked(address(this));
    }

    /// @notice Get raw balance for a strategy and token from Aqua
    /// @param strategyHash The strategy hash
    /// @param token The token address
    /// @return balance The raw balance amount
    /// @return tokensCount The number of tokens in the strategy (0xff = docked)
    function getRawBalance(bytes32 strategyHash, address token)
        external
        view
        returns (uint248 balance, uint8 tokensCount)
    {
        return _aqua.rawBalances(address(this), swapVMRouter, strategyHash, token);
    }

    /// @notice Get stored tokens for a strategy
    /// @param strategyHash The strategy hash
    /// @return The token addresses stored when the strategy was shipped
    function getStrategyTokens(bytes32 strategyHash) external view returns (address[] memory) {
        return _strategyTokens[strategyHash];
    }

    /// @notice Get token balance held by this account
    /// @param token The token address
    /// @return The actual token balance
    function getTokenBalance(address token) external view returns (uint256) {
        return OZERC20(token).balanceOf(address(this));
    }
}
