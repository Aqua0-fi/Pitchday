// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {SafeCast} from "@uniswap/v4-core/libraries/SafeCast.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Aqua0BaseHook} from "../Aqua0BaseHook.sol";
import {SharedLiquidityPool} from "../SharedLiquidityPool.sol";

/// @title TrancheFi Hook -- Structured LP Tranches for Uniswap V4, integrated with Aqua0
/// @notice Implements a Senior/Junior tranche system for LP positions.
///         Senior LPs get priority fees (target APY) and IL protection.
///         Junior LPs absorb IL first but get all excess fees (unlimited upside).
///         Inherits Aqua0BaseHook for JIT shared liquidity from the Aqua0 SharedLiquidityPool.
contract TranchesHook is IHooks, Aqua0BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    // ============ Enums ============

    enum Tranche {
        SENIOR,
        JUNIOR
    }

    // ============ Structs ============

    struct Position {
        Tranche tranche;
        uint256 amount; // liquidity amount tracked by the hook
        uint256 depositBlock; // for min-block anti-flash-loan lock
        uint256 rewardDebt0; // rewardPerShare snapshot for currency0
        uint256 rewardDebt1; // rewardPerShare snapshot for currency1
        uint160 depositSqrtPriceX96; // price at deposit for IL calculation
    }

    struct PoolConfig {
        uint256 seniorTargetAPY; // basis points, e.g. 500 = 5.00%
        uint256 maxSeniorRatio; // basis points, e.g. 8000 = 80%
        uint256 totalSeniorLiquidity;
        uint256 totalJuniorLiquidity;
        uint256 accumulatedFeesSenior;
        uint256 accumulatedFeesJunior;
        uint256 rewardPerShareSenior0; // currency0 fees, scaled by PRECISION
        uint256 rewardPerShareSenior1; // currency1 fees, scaled by PRECISION
        uint256 rewardPerShareJunior0; // currency0 fees, scaled by PRECISION
        uint256 rewardPerShareJunior1; // currency1 fees, scaled by PRECISION
        uint256 lastUpdateTimestamp;
        uint160 initialSqrtPriceX96; // price at pool init, for IL calc
        bool initialized;
        uint160 lastSwapSqrtPriceX96; // committed price from most recent swap
        uint256 lastSwapBlock; // block of most recent swap (prevents same-block manipulation)
    }

    // ============ Constants ============

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MIN_BLOCKS_LOCK = 100; // anti-flash-loan
    uint128 public constant TRANCHE_FEE_BIPS = 10; // 0.1% of swap output
    uint256 public constant MAX_APY_BIPS = 10_000; // 100% max
    uint256 public constant IL_RESERVE_BIPS = 1000; // 10% of junior fees → IL reserve
    uint256 public constant MAX_IL_BIPS = 2000; // cap IL compensation at 20%

    // ============ Immutables ============

    /// @dev deployer for initial RSC setup
    address public immutable DEPLOYER;

    // ============ Storage ============

    /// @dev Authorized Reactive Smart Contract (RSC) address
    address public authorizedRSC;

    /// @dev PoolId => PoolConfig
    mapping(PoolId => PoolConfig) public poolConfigs;

    /// @dev keccak256(lpAddress, poolId) => Position
    mapping(bytes32 => Position) public positions;

    /// @dev Pull-pattern claimable balances (lp => currency => amount)
    mapping(address => mapping(Currency => uint256)) public claimableBalance;

    /// @dev IL reserve funded by junior fees, used to compensate senior LPs
    mapping(PoolId => mapping(Currency => uint256)) public ilReserve;

    /// @dev Pre-registration to prevent hookData lpAddress spoofing
    mapping(address => bool) private _depositRegistered;
    mapping(address => Tranche) private _depositTranche;
    /// @dev Trusted router for atomic registration
    address public trustedRouter;

    // ============ Events ============

    event TranchDeposit(PoolId indexed poolId, address indexed lp, Tranche tranche, uint256 amount);
    event TrancheWithdraw(PoolId indexed poolId, address indexed lp, Tranche tranche, uint256 amount);
    event FeeDistributed(PoolId indexed poolId, uint256 seniorFees, uint256 juniorFees);
    event FeesClaimed(address indexed lp, PoolId indexed poolId, uint256 amount0, uint256 amount1);
    event PoolConfigured(PoolId indexed poolId, uint256 seniorTargetAPY, uint256 maxSeniorRatio);
    event RiskParameterAdjusted(PoolId indexed poolId, uint256 newSeniorTargetAPY);
    event AuthorizedRSCUpdated(address indexed oldRSC, address indexed newRSC);
    event TrustedRouterUpdated(address indexed oldRouter, address indexed newRouter);
    event ILCompensation(PoolId indexed poolId, address indexed lp, uint256 amount0, uint256 amount1);

    // ============ Errors ============

    error PoolNotInitialized();
    error MinBlockLockNotMet(uint256 currentBlock, uint256 depositBlock, uint256 minBlocks);
    error SeniorRatioExceeded(uint256 currentRatio, uint256 maxRatio);
    error NoPosition();
    error NoPendingFees();
    error Unauthorized();
    error ZeroAddress();
    error TrancheMismatch();
    error DepositNotRegistered();
    error NotTrustedRouter();
    error HookNotImplemented();

    // ============ Constructor ============

    constructor(IPoolManager _manager, SharedLiquidityPool _sharedPool, address _owner) Aqua0BaseHook(_manager, _sharedPool) {
        if (_owner == address(0)) revert ZeroAddress();
        DEPLOYER = _owner;
    }

    // ============ Receive ETH ============

    receive() external payable {}

    // ============ Hook Permissions ============

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: true, // Aqua0 JIT: inject virtual liquidity before swap
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: true
        });
    }

    // ============ Hook Callbacks ============

    /// @notice Called before each swap. Injects Aqua0 JIT virtual liquidity.
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _addVirtualLiquidity(key);
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Called after pool initialization. Configures tranche parameters.
    function afterInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96, int24)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        PoolId poolId = key.toId();

        poolConfigs[poolId] = PoolConfig({
            seniorTargetAPY: 500, // 5% default
            maxSeniorRatio: 8000, // 80% default
            totalSeniorLiquidity: 0,
            totalJuniorLiquidity: 0,
            accumulatedFeesSenior: 0,
            accumulatedFeesJunior: 0,
            rewardPerShareSenior0: 0,
            rewardPerShareSenior1: 0,
            rewardPerShareJunior0: 0,
            rewardPerShareJunior1: 0,
            lastUpdateTimestamp: block.timestamp,
            initialSqrtPriceX96: sqrtPriceX96,
            initialized: true,
            lastSwapSqrtPriceX96: sqrtPriceX96,
            lastSwapBlock: 0
        });

        emit PoolConfigured(poolId, 500, 8000);

        return IHooks.afterInitialize.selector;
    }

    /// @notice Called after liquidity is added via V4 modifyLiquidity.
    /// @dev Legacy path: registers tranche via hookData. JIT calls pass empty hookData → early return.
    ///      New path (Phase 2): tranche deposits go through recordVirtualDeposit instead.
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        if (hookData.length == 0) {
            return (IHooks.afterAddLiquidity.selector, toBalanceDelta(0, 0));
        }

        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];

        (address lpAddress, Tranche tranche) = abi.decode(hookData, (address, Tranche));

        // Validate pre-registration (prevents hookData spoofing)
        if (!_depositRegistered[lpAddress] || _depositTranche[lpAddress] != tranche) {
            revert DepositNotRegistered();
        }
        delete _depositRegistered[lpAddress];
        delete _depositTranche[lpAddress];

        uint256 amount = uint256(params.liquidityDelta);

        // Senior ratio cap (only enforced when juniors exist — allows senior-only bootstrap)
        if (tranche == Tranche.SENIOR && config.totalJuniorLiquidity > 0) {
            uint256 totalAfter = config.totalSeniorLiquidity + config.totalJuniorLiquidity + amount;
            uint256 seniorAfter = config.totalSeniorLiquidity + amount;
            uint256 ratio = (seniorAfter * BASIS_POINTS) / totalAfter;
            if (ratio > config.maxSeniorRatio) {
                revert SeniorRatioExceeded(ratio, config.maxSeniorRatio);
            }
        }

        _registerPosition(lpAddress, poolId, key, config, tranche, amount);
        emit TranchDeposit(poolId, lpAddress, tranche, amount);

        return (IHooks.afterAddLiquidity.selector, toBalanceDelta(0, 0));
    }

    /// @notice Called after every swap. Removes JIT liquidity, settles Aqua0 deltas,
    ///         then takes tranche fee and distributes via waterfall.
    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        // --- Aqua0 JIT: remove virtual liquidity and settle deltas ---
        (bool hasJIT, ) = _removeVirtualLiquidity(key);
        if (hasJIT) {
            _settleVirtualLiquidityDeltas(key);
        }

        // --- TrancheFi fee logic ---
        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];

        if (!config.initialized) return (IHooks.afterSwap.selector, 0);

        // Skip fee when no LPs exist
        if (config.totalSeniorLiquidity + config.totalJuniorLiquidity == 0) {
            return (IHooks.afterSwap.selector, 0);
        }

        // Output currency is always determined by swap direction, regardless of exact-input/output
        (Currency feeCurrency, int128 outputAmount) = params.zeroForOne
            ? (key.currency1, delta.amount1())
            : (key.currency0, delta.amount0());

        // Output is negative for the pool (positive for swapper), we want absolute value
        if (outputAmount < 0) outputAmount = -outputAmount;
        if (outputAmount == 0) return (IHooks.afterSwap.selector, 0);

        // Upcast to uint256 before multiplication to prevent uint128 overflow
        uint256 feeAmount = uint256(uint128(outputAmount)) * uint256(TRANCHE_FEE_BIPS) / BASIS_POINTS;
        if (feeAmount == 0) return (IHooks.afterSwap.selector, 0);

        // Skip take if fee too small to distribute
        uint256 totalLiquidity = config.totalSeniorLiquidity + config.totalJuniorLiquidity;
        if ((feeAmount * PRECISION) / totalLiquidity == 0) {
            return (IHooks.afterSwap.selector, 0);
        }

        // Determine which currency index this fee belongs to
        bool isCurrency0 = Currency.unwrap(feeCurrency) == Currency.unwrap(key.currency0);

        // Distribute via waterfall (updates rewardPerShare for LPs to claim)
        _distributeWaterfall(poolId, key, config, feeAmount, isCurrency0);

        // Take fee tokens from PoolManager to this hook (for LP claims later)
        poolManager.take(feeCurrency, address(this), feeAmount);

        // Store committed price for IL calculation (prevents same-block slot0 manipulation)
        (uint160 postSwapPrice,,,) = poolManager.getSlot0(poolId);
        config.lastSwapSqrtPriceX96 = postSwapPrice;
        config.lastSwapBlock = block.number;

        // Return fee as hook delta so PoolManager charges swapper the extra amount
        return (IHooks.afterSwap.selector, int128(uint128(feeAmount)));
    }

    /// @notice Called after liquidity is removed via V4 modifyLiquidity.
    /// @dev Tranche withdrawals go through recordVirtualWithdrawal (includes IL compensation).
    ///      This callback only fires for JIT burns and returns zero delta.
    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, toBalanceDelta(0, 0));
    }

    // ============ Unused Hook Stubs (required by IHooks) ============

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    // ============ External Functions ============

    /// @notice LPs call this to claim accumulated tranche fees
    function claimFees(PoolKey calldata key) external {
        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];
        bytes32 posKey = _positionKey(msg.sender, poolId);
        Position storage pos = positions[posKey];

        if (pos.amount == 0) revert NoPosition();
        if (block.number - pos.depositBlock < MIN_BLOCKS_LOCK) {
            revert MinBlockLockNotMet(block.number, pos.depositBlock, MIN_BLOCKS_LOCK);
        }

        _claimFeesInternal(msg.sender, poolId, key, config, pos);
    }

    /// @notice Pull pattern: LP withdraws claimable balance
    function withdrawFees(Currency currency) external {
        uint256 amount = claimableBalance[msg.sender][currency];
        if (amount == 0) revert NoPendingFees();

        claimableBalance[msg.sender][currency] -= amount;
        if (currency.isAddressZero()) {
            (bool success,) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(Currency.unwrap(currency)).safeTransfer(msg.sender, amount);
        }
    }

    // ============ Virtual Position Functions (SharedPool flow) ============

    /// @notice Record a virtual tranche deposit. Called by trusted router after depositing
    ///         into SharedLiquidityPool. Tracks the LP's tranche and position amount.
    /// @param lp       The LP address
    /// @param key      The pool key
    /// @param tranche  SENIOR or JUNIOR
    /// @param amount   Liquidity amount (SharedPool virtual liquidity units)
    function recordVirtualDeposit(address lp, PoolKey calldata key, Tranche tranche, uint256 amount) external {
        if (msg.sender != trustedRouter) revert NotTrustedRouter();

        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];
        if (!config.initialized) revert PoolNotInitialized();

        // Senior ratio cap (only enforced when juniors exist — allows senior-only bootstrap)
        if (tranche == Tranche.SENIOR && config.totalJuniorLiquidity > 0) {
            uint256 totalAfter = config.totalSeniorLiquidity + config.totalJuniorLiquidity + amount;
            uint256 seniorAfter = config.totalSeniorLiquidity + amount;
            uint256 ratio = (seniorAfter * BASIS_POINTS) / totalAfter;
            if (ratio > config.maxSeniorRatio) {
                revert SeniorRatioExceeded(ratio, config.maxSeniorRatio);
            }
        }

        // Register or accumulate position
        _registerPosition(lp, poolId, key, config, tranche, amount);

        emit TranchDeposit(poolId, lp, tranche, amount);
    }

    /// @notice Record a virtual tranche withdrawal. Called by trusted router before removing
    ///         from SharedLiquidityPool. Auto-claims pending fees and updates tracking.
    /// @param lp       The LP address
    /// @param key      The pool key
    /// @param amount   Liquidity amount to withdraw (0 = full position)
    function recordVirtualWithdrawal(address lp, PoolKey calldata key, uint256 amount) external {
        if (msg.sender != trustedRouter) revert NotTrustedRouter();

        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];
        bytes32 posKey = _positionKey(lp, poolId);
        Position storage pos = positions[posKey];

        if (pos.amount == 0) revert NoPosition();

        // Anti flash-loan lock
        if (block.number - pos.depositBlock < MIN_BLOCKS_LOCK) {
            revert MinBlockLockNotMet(block.number, pos.depositBlock, MIN_BLOCKS_LOCK);
        }

        // Auto-claim pending fees
        _claimFeesInternal(lp, poolId, key, config, pos);

        // Determine removal amount
        uint256 removedAmount = amount == 0 ? pos.amount : amount;
        if (removedAmount > pos.amount) removedAmount = pos.amount;

        // Cache tranche before position may be deleted
        Tranche tranche = pos.tranche;

        // IL compensation for senior LPs (before pool total update)
        if (tranche == Tranche.SENIOR) {
            _compensateIL(lp, poolId, key, config, pos, removedAmount);
        }

        // Update pool totals
        if (tranche == Tranche.SENIOR) {
            config.totalSeniorLiquidity -= removedAmount;
        } else {
            config.totalJuniorLiquidity -= removedAmount;
        }

        // Update or delete position
        pos.amount -= removedAmount;
        if (pos.amount == 0) {
            delete positions[posKey];
        } else {
            (uint256 rps0, uint256 rps1) = _getRewardPerShare(config, tranche);
            pos.rewardDebt0 = (pos.amount * rps0) / PRECISION;
            pos.rewardDebt1 = (pos.amount * rps1) / PRECISION;
        }

        emit TrancheWithdraw(poolId, lp, tranche, removedAmount);
    }

    // ============ External Functions ============

    /// @notice Called by Reactive Network RSC to adjust risk parameters
    function adjustRiskParameter(PoolKey calldata key, uint256 newSeniorTargetAPY) external {
        if (msg.sender != authorizedRSC) revert Unauthorized();
        require(newSeniorTargetAPY <= MAX_APY_BIPS, "APY exceeds max");
        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];
        if (!config.initialized) revert PoolNotInitialized();

        config.seniorTargetAPY = newSeniorTargetAPY;

        emit RiskParameterAdjusted(poolId, newSeniorTargetAPY);
    }

    /// @notice Set the authorized RSC address
    function setAuthorizedRSC(address newRSC) external {
        if (msg.sender != DEPLOYER) revert Unauthorized();
        if (newRSC == address(0)) revert ZeroAddress();
        emit AuthorizedRSCUpdated(authorizedRSC, newRSC);
        authorizedRSC = newRSC;
    }

    /// @notice LP pre-registers intent to deposit
    function registerDeposit(Tranche tranche) external {
        _depositRegistered[msg.sender] = true;
        _depositTranche[msg.sender] = tranche;
    }

    // ============ Trusted Router Functions ============

    /// @notice Set the trusted router for atomic registration (only DEPLOYER)
    function setTrustedRouter(address _router) external {
        if (msg.sender != DEPLOYER) revert Unauthorized();
        if (_router == address(0)) revert ZeroAddress();
        emit TrustedRouterUpdated(trustedRouter, _router);
        trustedRouter = _router;
    }

    /// @notice Register deposit on behalf of LP (only trusted router)
    function registerDepositFor(address lp, Tranche tranche) external {
        if (msg.sender != trustedRouter) revert NotTrustedRouter();
        _depositRegistered[lp] = true;
        _depositTranche[lp] = tranche;
    }

    // ============ Internal Functions ============

    /// @dev Register or accumulate a position
    function _registerPosition(
        address lpAddress,
        PoolId poolId,
        PoolKey calldata key,
        PoolConfig storage config,
        Tranche tranche,
        uint256 amount
    ) internal {
        bytes32 posKey = _positionKey(lpAddress, poolId);
        Position storage existing = positions[posKey];

        if (existing.amount > 0) {
            if (tranche != existing.tranche) revert TrancheMismatch();

            (uint256 rps0, uint256 rps1) = _getRewardPerShare(config, existing.tranche);

            // Only claim fees if MIN_BLOCKS_LOCK has passed (prevents flash-loan fee extraction)
            if (block.number - existing.depositBlock >= MIN_BLOCKS_LOCK) {
                _claimFeesInternal(lpAddress, poolId, key, config, existing);
            } else {
                // Update reward debt without claiming to prevent loss of accrued fees
                existing.rewardDebt0 = (existing.amount * rps0) / PRECISION;
                existing.rewardDebt1 = (existing.amount * rps1) / PRECISION;
            }

            existing.amount += amount;
            existing.depositBlock = block.number; // Reset lock for new deposit
            existing.rewardDebt0 = (existing.amount * rps0) / PRECISION;
            existing.rewardDebt1 = (existing.amount * rps1) / PRECISION;

            if (existing.tranche == Tranche.SENIOR) {
                config.totalSeniorLiquidity += amount;
            } else {
                config.totalJuniorLiquidity += amount;
            }
        } else {
            (uint256 rps0, uint256 rps1) = _getRewardPerShare(config, tranche);

            // Fix #6: Use committed prior-block price to prevent same-block sandwich manipulation
            uint160 sqrtPrice;
            if (config.lastSwapBlock > 0 && config.lastSwapBlock < block.number) {
                sqrtPrice = config.lastSwapSqrtPriceX96;
            } else {
                // Fallback to live price when no prior swap committed (pool initialization)
                (sqrtPrice,,,) = poolManager.getSlot0(poolId);
            }

            positions[posKey] = Position({
                tranche: tranche,
                amount: amount,
                depositBlock: block.number,
                rewardDebt0: (amount * rps0) / PRECISION,
                rewardDebt1: (amount * rps1) / PRECISION,
                depositSqrtPriceX96: sqrtPrice
            });

            if (tranche == Tranche.SENIOR) {
                config.totalSeniorLiquidity += amount;
            } else {
                config.totalJuniorLiquidity += amount;
            }
        }
    }

    /// @dev Get rewardPerShare pair for a tranche
    function _getRewardPerShare(PoolConfig storage config, Tranche tranche)
        internal
        view
        returns (uint256 rps0, uint256 rps1)
    {
        if (tranche == Tranche.SENIOR) {
            rps0 = config.rewardPerShareSenior0;
            rps1 = config.rewardPerShareSenior1;
        } else {
            rps0 = config.rewardPerShareJunior0;
            rps1 = config.rewardPerShareJunior1;
        }
    }

    /// @dev Waterfall fee distribution: Senior gets priority boost, Junior gets the rest.
    ///      Funds IL reserve from junior fees before distribution.
    function _distributeWaterfall(
        PoolId poolId,
        PoolKey calldata key,
        PoolConfig storage config,
        uint256 totalFees,
        bool isCurrency0
    ) internal {
        uint256 timeDelta = block.timestamp - config.lastUpdateTimestamp;
        config.lastUpdateTimestamp = block.timestamp;

        uint256 seniorOwed = 0;
        uint256 totalLiquidity = config.totalSeniorLiquidity + config.totalJuniorLiquidity;

        if (config.totalSeniorLiquidity > 0 && totalLiquidity > 0) {
            uint256 seniorShare = (totalFees * config.totalSeniorLiquidity) / totalLiquidity;
            // Annualize the APY boost: scale seniorTargetAPY (bips/year) by actual time elapsed
            uint256 annualSeconds = 365 days;
            if (timeDelta > 0 && config.seniorTargetAPY > 0) {
                uint256 priorityBoost = (config.seniorTargetAPY * timeDelta) / annualSeconds;
                // Ensure at least 1 bip boost when timeDelta > 0 to preserve priority guarantee
                if (priorityBoost == 0) priorityBoost = 1;
                uint256 priorityMultiplier = BASIS_POINTS + priorityBoost;
                seniorOwed = (seniorShare * priorityMultiplier) / BASIS_POINTS;
                if (seniorOwed > totalFees) seniorOwed = totalFees;
            } else {
                seniorOwed = seniorShare;
            }
        }

        uint256 seniorFees;
        uint256 juniorFees;

        if (seniorOwed >= totalFees) {
            seniorFees = totalFees;
            juniorFees = 0;
        } else {
            seniorFees = seniorOwed;
            juniorFees = totalFees - seniorOwed;
        }

        // Fund IL reserve from junior fees (before distribution)
        if (juniorFees > 0) {
            uint256 ilFunding = (juniorFees * IL_RESERVE_BIPS) / BASIS_POINTS;
            Currency reserveCurrency = isCurrency0 ? key.currency0 : key.currency1;
            ilReserve[poolId][reserveCurrency] += ilFunding;
            juniorFees -= ilFunding;
        }

        if (seniorFees > 0 && config.totalSeniorLiquidity > 0) {
            uint256 increment = (seniorFees * PRECISION) / config.totalSeniorLiquidity;
            // Route truncation dust to IL reserve instead of locking it permanently
            uint256 credited = (increment * config.totalSeniorLiquidity) / PRECISION;
            uint256 remainder = seniorFees - credited;
            if (remainder > 0) {
                Currency reserveCurrency = isCurrency0 ? key.currency0 : key.currency1;
                ilReserve[poolId][reserveCurrency] += remainder;
            }
            if (isCurrency0) {
                config.rewardPerShareSenior0 += increment;
            } else {
                config.rewardPerShareSenior1 += increment;
            }
            config.accumulatedFeesSenior += seniorFees;
        }

        if (juniorFees > 0 && config.totalJuniorLiquidity > 0) {
            uint256 increment = (juniorFees * PRECISION) / config.totalJuniorLiquidity;
            // Route truncation dust to IL reserve
            uint256 credited = (increment * config.totalJuniorLiquidity) / PRECISION;
            uint256 remainder = juniorFees - credited;
            if (remainder > 0) {
                Currency reserveCurrency = isCurrency0 ? key.currency0 : key.currency1;
                ilReserve[poolId][reserveCurrency] += remainder;
            }
            if (isCurrency0) {
                config.rewardPerShareJunior0 += increment;
            } else {
                config.rewardPerShareJunior1 += increment;
            }
            config.accumulatedFeesJunior += juniorFees;
        } else if (juniorFees > 0 && config.totalJuniorLiquidity == 0) {
            if (config.totalSeniorLiquidity > 0) {
                uint256 increment = (juniorFees * PRECISION) / config.totalSeniorLiquidity;
                if (isCurrency0) {
                    config.rewardPerShareSenior0 += increment;
                } else {
                    config.rewardPerShareSenior1 += increment;
                }
                config.accumulatedFeesSenior += juniorFees;
            }
        }

        emit FeeDistributed(poolId, seniorFees, juniorFees);
    }

    /// @dev Internal fee claim logic (pull pattern)
    function _claimFeesInternal(
        address lp,
        PoolId poolId,
        PoolKey calldata key,
        PoolConfig storage config,
        Position storage pos
    ) internal {
        (uint256 rps0, uint256 rps1) = _getRewardPerShare(config, pos.tranche);

        uint256 pending0 = (pos.amount * rps0 / PRECISION) - pos.rewardDebt0;
        uint256 pending1 = (pos.amount * rps1 / PRECISION) - pos.rewardDebt1;

        if (pending0 > 0 || pending1 > 0) {
            pos.rewardDebt0 = pos.amount * rps0 / PRECISION;
            pos.rewardDebt1 = pos.amount * rps1 / PRECISION;

            if (pending0 > 0) {
                claimableBalance[lp][key.currency0] += pending0;
            }
            if (pending1 > 0) {
                claimableBalance[lp][key.currency1] += pending1;
            }

            emit FeesClaimed(lp, poolId, pending0, pending1);
        }
    }

    // ============ IL Protection ============

    /// @dev Calculate impermanent loss in basis points from sqrt price movement.
    ///      IL = (a - b)^2 / (a^2 + b^2) where a = sqrtPriceInitial, b = sqrtPriceCurrent.
    ///      Values are shifted >>48 to prevent uint256 overflow (160-bit squared = 320 bits).
    function _calculateILBips(uint160 sqrtPriceInitial, uint160 sqrtPriceCurrent) internal pure returns (uint256) {
        uint256 a = uint256(sqrtPriceInitial) >> 48;
        uint256 b = uint256(sqrtPriceCurrent) >> 48;
        if (a == 0 || b == 0) return 0;

        uint256 diff = a > b ? a - b : b - a;
        uint256 numerator = diff * diff * BASIS_POINTS;
        uint256 denominator = a * a + b * b;

        uint256 ilBips = numerator / denominator;
        return ilBips > MAX_IL_BIPS ? MAX_IL_BIPS : ilBips;
    }

    /// @dev Compensate a senior LP for IL from the IL reserve.
    ///      Called during withdrawal before pool totals are decremented.
    function _compensateIL(
        address lp,
        PoolId poolId,
        PoolKey calldata key,
        PoolConfig storage config,
        Position storage pos,
        uint256 removedAmount
    ) internal {
        // Use committed price from a prior block to prevent same-block slot0 manipulation.
        // If no prior-block price exists, skip IL compensation (safe default).
        if (config.lastSwapBlock == 0 || config.lastSwapBlock >= block.number) return;
        uint160 currentSqrtPrice = config.lastSwapSqrtPriceX96;
        uint256 ilBips = _calculateILBips(pos.depositSqrtPriceX96, currentSqrtPrice);

        if (ilBips == 0 || config.totalSeniorLiquidity == 0) return;

        uint256 comp0;
        uint256 comp1;

        // Currency0: proportional share of IL reserve, scaled by IL severity
        uint256 reserve0 = ilReserve[poolId][key.currency0];
        if (reserve0 > 0) {
            uint256 share0 = (reserve0 * removedAmount) / config.totalSeniorLiquidity;
            comp0 = (share0 * ilBips) / MAX_IL_BIPS;
            if (comp0 > reserve0) comp0 = reserve0;
            ilReserve[poolId][key.currency0] -= comp0;
            claimableBalance[lp][key.currency0] += comp0;
        }

        // Currency1: proportional share of IL reserve, scaled by IL severity
        uint256 reserve1 = ilReserve[poolId][key.currency1];
        if (reserve1 > 0) {
            uint256 share1 = (reserve1 * removedAmount) / config.totalSeniorLiquidity;
            comp1 = (share1 * ilBips) / MAX_IL_BIPS;
            if (comp1 > reserve1) comp1 = reserve1;
            ilReserve[poolId][key.currency1] -= comp1;
            claimableBalance[lp][key.currency1] += comp1;
        }

        if (comp0 > 0 || comp1 > 0) {
            emit ILCompensation(poolId, lp, comp0, comp1);
        }
    }

    // ============ View Functions ============

    function _positionKey(address lp, PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(lp, PoolId.unwrap(poolId)));
    }

    /// @notice Get pending fees for an LP (both currencies)
    function pendingFees(address lp, PoolKey calldata key) external view returns (uint256 pending0, uint256 pending1) {
        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];
        bytes32 posKey = _positionKey(lp, poolId);
        Position storage pos = positions[posKey];

        if (pos.amount == 0) return (0, 0);

        (uint256 rps0, uint256 rps1) = _getRewardPerShare(config, pos.tranche);

        pending0 = (pos.amount * rps0 / PRECISION) - pos.rewardDebt0;
        pending1 = (pos.amount * rps1 / PRECISION) - pos.rewardDebt1;
    }

    /// @notice Get pool tranche stats
    function getPoolStats(PoolKey calldata key)
        external
        view
        returns (
            uint256 totalSenior,
            uint256 totalJunior,
            uint256 seniorFees,
            uint256 juniorFees,
            uint256 seniorAPY,
            uint256 seniorRatio
        )
    {
        PoolId poolId = key.toId();
        PoolConfig storage config = poolConfigs[poolId];

        totalSenior = config.totalSeniorLiquidity;
        totalJunior = config.totalJuniorLiquidity;
        seniorFees = config.accumulatedFeesSenior;
        juniorFees = config.accumulatedFeesJunior;
        seniorAPY = config.seniorTargetAPY;

        uint256 total = totalSenior + totalJunior;
        seniorRatio = total > 0 ? (totalSenior * BASIS_POINTS) / total : 0;
    }
}
