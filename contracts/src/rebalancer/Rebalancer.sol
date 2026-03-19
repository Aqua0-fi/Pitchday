// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { RebalanceOperation, RebalanceStatus } from "../lib/Types.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";
import { Account } from "../lp/Account.sol";

/// @title Rebalancer
/// @author Aqua0 Team
/// @notice Monitors liquidity utilization and triggers cross-chain rebalancing
/// @dev Rebalancing flow:
///      1. triggerRebalance() - Create operation, start monitoring
///      2. executeDock() - Dock strategy on source chain (zeros virtual balance)
///      3. executeBridgeStargate() / executeBridgeCCTP() - Bridge tokens to destination chain
///      4. confirmRebalance() - Confirm completion after destination ship()
///
///      Key constraints from architecture:
///      - dock() only zeros virtual balances, does NOT transfer tokens
///      - Tokens remain in LP Smart Account until explicit bridge
///      - Rebalance txs can only be batched from same source chain
///      - Base is the default source chain for deposits
///
///      Deployed behind ERC1967Proxy (UUPS pattern) for upgradeability.
contract Rebalancer is Initializable, Ownable, ReentrancyGuard, UUPSUpgradeable {
    /// @notice Authorized rebalancer address (backend service)
    address public rebalancer;

    /// @notice Mapping of operation ID to RebalanceOperation
    mapping(bytes32 => RebalanceOperation) public operations;

    /// @notice Storage gap for future upgrades
    uint256[48] private __gap;

    /// @notice Modifier to restrict access to authorized rebalancer
    modifier onlyRebalancer() {
        if (msg.sender != rebalancer) revert Errors.NotRebalancer();
        _;
    }

    /// @notice Constructor — disables initializers on the implementation contract
    constructor() Ownable(address(1)) {
        _disableInitializers();
    }

    /// @notice Initialize the rebalancer (called once per proxy deployment)
    /// @param _owner The owner address
    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        _transferOwnership(_owner);
        rebalancer = _owner;
    }

    /// @notice Authorize UUPS upgrades — only owner can upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /// @notice Set rebalancer address
    /// @param _rebalancer The new rebalancer address
    function setRebalancer(address _rebalancer) external onlyOwner {
        if (_rebalancer == address(0)) revert Errors.ZeroAddress();
        rebalancer = _rebalancer;
    }

    /// @notice Trigger a rebalancing operation
    /// @param lpAccount The LP account address
    /// @param srcChainId Source chain ID
    /// @param dstChainId Destination chain ID
    /// @param token The token to rebalance
    /// @param amount The amount to rebalance
    /// @return operationId The operation ID
    function triggerRebalance(address lpAccount, uint32 srcChainId, uint32 dstChainId, address token, uint256 amount)
        external
        onlyRebalancer
        nonReentrant
        returns (bytes32 operationId)
    {
        if (lpAccount == address(0)) revert Errors.ZeroAddress();
        if (token == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();
        if (srcChainId == dstChainId) revert Errors.InvalidInput();

        // Verify LP account has authorized this rebalancer
        Account account = Account(payable(lpAccount));
        if (!account.rebalancerAuthorized() || account.rebalancer() != address(this)) {
            revert Errors.NotAuthorized();
        }

        operationId = keccak256(abi.encode(lpAccount, srcChainId, dstChainId, token, amount, block.timestamp));

        operations[operationId] = RebalanceOperation({
            lpAccount: lpAccount,
            srcChainId: srcChainId,
            dstChainId: dstChainId,
            token: token,
            amount: amount,
            messageGuid: bytes32(0),
            status: RebalanceStatus.PENDING,
            initiatedAt: block.timestamp,
            completedAt: 0
        });

        emit Events.RebalanceTriggered(operationId, lpAccount, srcChainId, dstChainId, token, amount);
    }

    /// @notice Execute dock phase of rebalance
    /// @dev Docks the source strategy to zero virtual balances
    /// @param operationId The operation ID
    /// @param strategyHash The strategy hash to dock
    function executeDock(bytes32 operationId, bytes32 strategyHash) external onlyRebalancer nonReentrant {
        RebalanceOperation storage operation = operations[operationId];
        if (operation.lpAccount == address(0)) revert Errors.RebalanceOperationNotFound();
        if (operation.status != RebalanceStatus.PENDING) {
            revert Errors.InvalidInput();
        }

        // Dock strategy on source chain (zeros virtual balance in Aqua)
        Account account = Account(payable(operation.lpAccount));
        account.dock(strategyHash);

        operation.status = RebalanceStatus.DOCKED;
    }

    /// @notice Execute bridge phase via Stargate/LayerZero — calls Account.bridgeStargate()
    /// @dev Transitions operation from DOCKED → BRIDGING. The Account approves tokens to
    ///      StargateAdapter and calls bridgeWithCompose, returning a LayerZero GUID.
    /// @param operationId The operation ID
    /// @param dstEid Destination LayerZero endpoint ID
    /// @param dstComposer The Composer address on the destination chain
    /// @param composeMsg ABI-encoded compose payload for the destination Composer
    /// @param token The token to bridge
    /// @param amount The amount to bridge
    /// @param minAmount The minimum amount to receive (slippage protection)
    /// @param lzReceiveGas Gas allocated for lzReceive on destination
    /// @param lzComposeGas Gas allocated for lzCompose on destination
    function executeBridgeStargate(
        bytes32 operationId,
        uint32 dstEid,
        address dstComposer,
        bytes calldata composeMsg,
        address token,
        uint256 amount,
        uint256 minAmount,
        uint128 lzReceiveGas,
        uint128 lzComposeGas
    ) external payable onlyRebalancer nonReentrant {
        RebalanceOperation storage operation = operations[operationId];
        if (operation.lpAccount == address(0)) revert Errors.RebalanceOperationNotFound();
        if (operation.status != RebalanceStatus.DOCKED) revert Errors.InvalidInput();

        Account account = Account(payable(operation.lpAccount));
        bytes32 guid = account.bridgeStargate{ value: msg.value }(
            dstEid, dstComposer, composeMsg, token, amount, minAmount, lzReceiveGas, lzComposeGas
        );

        operation.messageGuid = guid;
        operation.status = RebalanceStatus.BRIDGING;
    }

    /// @notice Execute bridge phase via CCTP — calls Account.bridgeCCTP() to send USDC cross-chain
    /// @dev Transitions operation from DOCKED → BRIDGING.
    /// @param operationId The operation ID
    /// @param dstDomain The CCTP destination domain ID
    /// @param dstComposer The CCTPComposer address on the destination chain
    /// @param hookData ABI-encoded hook payload for the destination CCTPComposer
    /// @param token The token to bridge (USDC)
    /// @param amount The amount to bridge
    /// @param maxFee The maximum fee for the CCTP transfer
    /// @param minFinalityThreshold The minimum finality threshold for fast transfer
    function executeBridgeCCTP(
        bytes32 operationId,
        uint32 dstDomain,
        address dstComposer,
        bytes calldata hookData,
        address token,
        uint256 amount,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external payable onlyRebalancer nonReentrant {
        RebalanceOperation storage operation = operations[operationId];
        if (operation.lpAccount == address(0)) revert Errors.RebalanceOperationNotFound();
        if (operation.status != RebalanceStatus.DOCKED) revert Errors.InvalidInput();

        Account account = Account(payable(operation.lpAccount));
        uint64 nonce = account.bridgeCCTP{ value: msg.value }(
            dstDomain, dstComposer, hookData, token, amount, maxFee, minFinalityThreshold
        );

        operation.messageGuid = bytes32(uint256(nonce));
        operation.status = RebalanceStatus.BRIDGING;
    }

    /// @notice Record that bridging has started (fallback for manual/external bridges)
    /// @dev Called after Stargate send() is initiated externally
    /// @param operationId The operation ID
    /// @param messageGuid The LayerZero message GUID
    function recordBridging(bytes32 operationId, bytes32 messageGuid) external onlyRebalancer nonReentrant {
        RebalanceOperation storage operation = operations[operationId];
        if (operation.lpAccount == address(0)) revert Errors.RebalanceOperationNotFound();
        if (operation.status != RebalanceStatus.DOCKED) {
            revert Errors.InvalidInput();
        }

        operation.messageGuid = messageGuid;
        operation.status = RebalanceStatus.BRIDGING;
    }

    /// @notice Confirm rebalancing completed
    /// @dev Called after destination chain ship() succeeds
    /// @param operationId The operation ID
    function confirmRebalance(bytes32 operationId) external onlyRebalancer nonReentrant {
        RebalanceOperation storage operation = operations[operationId];
        if (operation.lpAccount == address(0)) revert Errors.RebalanceOperationNotFound();
        if (operation.status != RebalanceStatus.BRIDGING) {
            revert Errors.InvalidInput();
        }

        operation.status = RebalanceStatus.COMPLETED;
        operation.completedAt = block.timestamp;

        emit Events.RebalanceCompleted(operationId, operation.messageGuid);
    }

    /// @notice Mark rebalance as failed
    /// @param operationId The operation ID
    /// @param reason The failure reason
    function failRebalance(bytes32 operationId, string memory reason) external onlyRebalancer nonReentrant {
        RebalanceOperation storage operation = operations[operationId];
        if (operation.lpAccount == address(0)) revert Errors.RebalanceOperationNotFound();
        if (operation.status == RebalanceStatus.COMPLETED || operation.status == RebalanceStatus.FAILED) {
            revert Errors.InvalidInput();
        }

        operation.status = RebalanceStatus.FAILED;
        operation.completedAt = block.timestamp;

        emit Events.RebalanceFailed(operationId, reason);
    }

    /// @notice Get rebalance operation details
    /// @param operationId The operation ID
    /// @return The RebalanceOperation struct
    function getOperation(bytes32 operationId) external view returns (RebalanceOperation memory) {
        RebalanceOperation memory operation = operations[operationId];
        if (operation.lpAccount == address(0)) revert Errors.RebalanceOperationNotFound();
        return operation;
    }

    /// @notice Check if an operation exists
    /// @param operationId The operation ID
    /// @return Whether the operation exists
    function operationExists(bytes32 operationId) external view returns (bool) {
        return operations[operationId].lpAccount != address(0);
    }
}
