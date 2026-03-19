// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {AbstractReactive} from "reactive-lib/abstract-base/AbstractReactive.sol";
import {IReactive} from "reactive-lib/interfaces/IReactive.sol";
import {ISystemContract} from "reactive-lib/interfaces/ISystemContract.sol";

/// @title TrancheFi Volatility RSC -- Cross-Chain Weighted-Price Volatility Monitor
/// @notice Deployed on Reactive Network. Subscribes to Uniswap V4 Swap events
///         across multiple chains, maintains per-chain sqrtPriceX96, computes an
///         equal-weighted average price, and tracks realized volatility via EMA of
///         squared log-returns. Emits Callbacks to adjust TranchesHook risk parameters
///         when the volatility regime changes.
contract TrancheFiVolatilityRSC is AbstractReactive {
    // ============ Constants ============

    /// @notice Uniswap V4 Swap event selector
    uint256 public constant SWAP_EVENT_TOPIC0 =
        uint256(keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"));

    /// @notice Callback gas limit for cross-chain calls
    uint64 public constant CALLBACK_GAS_LIMIT = 200_000;

    /// @notice EMA alpha factor (scaled by 1000): alpha=100 -> 10% weight to new observation
    uint256 public constant EMA_ALPHA = 100;
    uint256 public constant EMA_SCALE = 1000;

    /// @notice Volatility thresholds (squared-return EMA, scaled by 1e18)
    uint256 public constant LOW_THRESHOLD = 4e14; // ~20% annualized vol^2
    uint256 public constant HIGH_THRESHOLD = 36e14; // ~60% annualized vol^2

    /// @notice APY values for each volatility regime (basis points)
    uint256 public constant LOW_VOL_APY = 300; // 3%
    uint256 public constant MED_VOL_APY = 500; // 5%
    uint256 public constant HIGH_VOL_APY = 1000; // 10%

    // ============ Enums ============

    enum VolatilityRegime {
        LOW,
        MEDIUM,
        HIGH
    }

    // ============ State ============

    /// @notice Chain ID where the TranchesHook is deployed
    uint256 public immutable destinationChainId;

    /// @notice The callback receiver contract address on the destination chain
    address public immutable callbackReceiver;

    /// @notice Chain IDs being monitored
    uint256[] public monitoredChainIds;

    /// @notice Latest sqrtPriceX96 observed per chain
    mapping(uint256 => uint256) public chainPrices;

    /// @notice Last computed equal-weighted average sqrtPriceX96
    uint256 public lastWeightedPrice;

    /// @notice EMA of squared log-returns (scaled by 1e18)
    uint256 public volatilityEMA;

    /// @notice Current volatility regime
    VolatilityRegime public currentRegime;

    /// @notice Number of swap observations processed
    uint256 public observationCount;

    // ============ Events ============

    event SwapObserved(uint256 indexed chainId, uint256 sqrtPriceX96, uint256 weightedPrice, uint256 squaredReturn);
    event VolatilityRegimeChanged(VolatilityRegime oldRegime, VolatilityRegime newRegime, uint256 newAPY);

    // ============ Constructor ============

    /// @param _service Reactive Network system contract address
    /// @param _destinationChainId Chain ID where TranchesHook lives
    /// @param _callbackReceiver TrancheFiCallbackReceiver address on destination chain
    /// @param _chainIds Array of chain IDs to monitor for Swap events
    /// @param _poolManagers Corresponding PoolManager addresses (or address(0) for any)
    constructor(
        address _service,
        uint256 _destinationChainId,
        address _callbackReceiver,
        uint256[] memory _chainIds,
        address[] memory _poolManagers
    ) payable {
        service = ISystemContract(payable(_service));
        require(_chainIds.length == _poolManagers.length, "Array length mismatch");
        require(_chainIds.length > 0, "No chains to monitor");

        destinationChainId = _destinationChainId;
        callbackReceiver = _callbackReceiver;
        currentRegime = VolatilityRegime.MEDIUM;

        for (uint256 i = 0; i < _chainIds.length; i++) {
            monitoredChainIds.push(_chainIds[i]);
        }

        // Subscribe to Swap events on ALL monitored chains (only on Reactive Network)
        if (!vm) {
            for (uint256 i = 0; i < _chainIds.length; i++) {
                service.subscribe(
                    _chainIds[i],
                    _poolManagers[i],
                    SWAP_EVENT_TOPIC0,
                    REACTIVE_IGNORE,
                    REACTIVE_IGNORE,
                    REACTIVE_IGNORE
                );
            }
        }
    }

    // ============ Reactive Entry Point ============

    /// @notice Called by Reactive Network when a matching Swap event is detected
    function react(IReactive.LogRecord calldata log) external vmOnly {
        uint256 sqrtPriceX96 = uint256(uint160(uint256(bytes32(_sliceBytes(log.data, 64, 32)))));

        if (sqrtPriceX96 == 0) return;

        chainPrices[log.chain_id] = sqrtPriceX96;

        uint256 weightedPrice = _computeWeightedPrice();

        if (lastWeightedPrice > 0) {
            uint256 squaredReturn = _computeSquaredReturn(lastWeightedPrice, weightedPrice);

            volatilityEMA = (EMA_ALPHA * squaredReturn + (EMA_SCALE - EMA_ALPHA) * volatilityEMA) / EMA_SCALE;

            emit SwapObserved(log.chain_id, sqrtPriceX96, weightedPrice, squaredReturn);

            observationCount++;
            if (observationCount >= 5) {
                _checkRegimeChange();
            }
        }

        lastWeightedPrice = weightedPrice;
    }

    // ============ View Helpers ============

    function monitoredChainCount() external view returns (uint256) {
        return monitoredChainIds.length;
    }

    // ============ Internal ============

    function _computeWeightedPrice() internal view returns (uint256) {
        uint256 totalPrice = 0;
        uint256 activeChains = 0;
        for (uint256 i = 0; i < monitoredChainIds.length; i++) {
            uint256 price = chainPrices[monitoredChainIds[i]];
            if (price > 0) {
                totalPrice += price;
                activeChains++;
            }
        }
        return totalPrice / activeChains;
    }

    function _computeSquaredReturn(uint256 oldPrice, uint256 newPrice) internal pure returns (uint256) {
        uint256 diff = newPrice >= oldPrice ? newPrice - oldPrice : oldPrice - newPrice;

        uint256 change;
        if (diff > type(uint128).max) {
            change = (diff / oldPrice) * 2 * 1e18;
        } else {
            change = (diff * 2 * 1e18) / oldPrice;
        }

        uint256 MAX_CHANGE = 1e30;
        if (change > MAX_CHANGE) change = MAX_CHANGE;

        return (change * change) / 1e18;
    }

    function _checkRegimeChange() internal {
        VolatilityRegime newRegime;
        uint256 newAPY;

        if (volatilityEMA < LOW_THRESHOLD) {
            newRegime = VolatilityRegime.LOW;
            newAPY = LOW_VOL_APY;
        } else if (volatilityEMA > HIGH_THRESHOLD) {
            newRegime = VolatilityRegime.HIGH;
            newAPY = HIGH_VOL_APY;
        } else {
            newRegime = VolatilityRegime.MEDIUM;
            newAPY = MED_VOL_APY;
        }

        if (newRegime != currentRegime) {
            emit VolatilityRegimeChanged(currentRegime, newRegime, newAPY);
            currentRegime = newRegime;

            bytes memory payload =
                abi.encodeWithSignature("onVolatilityUpdate(address,uint256)", address(0), newAPY);

            emit Callback(destinationChainId, callbackReceiver, CALLBACK_GAS_LIMIT, payload);
        }
    }

    function _sliceBytes(bytes calldata data, uint256 offset, uint256 length) internal pure returns (bytes32 result) {
        require(data.length >= offset + length, "Slice out of bounds");
        assembly {
            result := calldataload(add(data.offset, offset))
        }
    }
}
