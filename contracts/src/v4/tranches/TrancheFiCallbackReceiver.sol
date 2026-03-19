// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {AbstractCallback} from "reactive-lib/abstract-base/AbstractCallback.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";

/// @notice Minimal interface for the TranchesHook risk adjustment
interface ITranchesHook {
    function adjustRiskParameter(PoolKey calldata key, uint256 newSeniorTargetAPY) external;
}

/// @title TrancheFi Callback Receiver -- Reactive Network -> destination chain bridge endpoint
/// @notice Deployed on the destination chain (e.g. Unichain). Receives volatility callbacks
///         from the Reactive Network RSC and relays risk-parameter adjustments to the TranchesHook.
contract TrancheFiCallbackReceiver is AbstractCallback {
    // ============ State ============

    /// @notice The TranchesHook contract on the destination chain
    ITranchesHook public immutable hook;

    /// @notice The deployer address (for admin functions)
    address public immutable deployer;

    /// @notice Stored PoolKey so the RSC only needs to send the new APY value
    PoolKey public poolKey;

    /// @notice Whether the pool key has been set
    bool public poolKeySet;

    // ============ Events ============

    event VolatilityCallbackReceived(address indexed rvmId, uint256 newSeniorTargetAPY);
    event PoolKeyUpdated();

    // ============ Errors ============

    error OnlyDeployer();
    error PoolKeyNotSet();

    // ============ Constructor ============

    /// @param _callbackSender The Reactive Network callback proxy on the destination chain
    /// @param _hook The TranchesHook contract address on the destination chain
    constructor(address _callbackSender, address _hook) AbstractCallback(_callbackSender) {
        hook = ITranchesHook(_hook);
        deployer = msg.sender;
    }

    // ============ Admin ============

    /// @notice Set the pool key that this receiver manages
    function setPoolKey(PoolKey calldata _key) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        poolKey = _key;
        poolKeySet = true;
        emit PoolKeyUpdated();
    }

    // ============ Reactive Callback ============

    /// @notice Called by Reactive Network when the volatility RSC detects a regime change
    /// @param _rvmId Auto-filled by Reactive Network with the RSC's RVM ID
    /// @param _newSeniorTargetAPY New senior target APY in basis points (e.g. 500 = 5%)
    function onVolatilityUpdate(address _rvmId, uint256 _newSeniorTargetAPY)
        external
        authorizedSenderOnly
        rvmIdOnly(_rvmId)
    {
        if (!poolKeySet) revert PoolKeyNotSet();

        hook.adjustRiskParameter(poolKey, _newSeniorTargetAPY);

        emit VolatilityCallbackReceived(_rvmId, _newSeniorTargetAPY);
    }
}
