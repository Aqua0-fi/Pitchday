// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {console} from "forge-std/console.sol";
import {IAqua0BaseHookMarker} from "./IAqua0BaseHookMarker.sol";

/// @title SharedLiquidityPool
/// @author Aqua0 Team
/// @notice Single contract that holds all LP deposits and tracks virtual positions per user
///         per Uniswap V4 pool + tick range. The Aqua0Hook reads aggregated positions
///         and settles swap deltas against this contract via flash accounting.
///
///         Lifecycle:
///           1. LP calls deposit() to bring tokens into the pool.
///           2. LP calls addPosition() to allocate a portion to a specific V4 pool + tick range.
///              This is purely virtual - no tokens leave this contract.
///           3. On each swap: Aqua0Hook calls modifyLiquidity(+) in beforeSwap and
///              modifyLiquidity(-) in afterSwap. The hook calls settleSwapDelta() to
///              transfer only the net swap impact in/out of this contract.
///           4. LP calls removePosition() then withdraw() to exit.
contract SharedLiquidityPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;

    // ─── Structs ─────────────────────────────────────────────────────────────

    /// @notice A user's virtual position in a specific pool at a specific tick range
    struct UserPosition {
        PoolId poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidityShares; // virtual liquidity requested
        uint256 token0Initial; // token0 backing this position
        uint256 token1Initial; // token1 backing this position
        bool active;
    }

    /// @notice Aggregated liquidity across all users for a (pool, tickLower, tickUpper) range
    struct RangeInfo {
        int24 tickLower;
        int24 tickUpper;
        uint128 totalLiquidity; // sum of all user shares
    }

    // ─── State ───────────────────────────────────────────────────────────────

    /// @notice user => token => free (unallocated) balance
    mapping(address => mapping(address => uint256)) public freeBalance;

    /// @notice user => token => accumulated fee balance available to claim
    mapping(address => mapping(address => uint256)) public earnedFees;

    /// @notice user => positionId => UserPosition
    mapping(address => mapping(bytes32 => UserPosition)) public userPositions;

    /// @notice user => list of positionIds (for enumeration)
    mapping(address => bytes32[]) private _userPositionIds;

    /// @notice poolId => rangeKey => RangeInfo
    ///         rangeKey = keccak256(abi.encode(tickLower, tickUpper))
    mapping(PoolId => mapping(bytes32 => RangeInfo)) public aggregatedRanges;

    /// @notice poolId => list of active rangeKeys
    mapping(PoolId => bytes32[]) private _poolRangeKeys;

    /// @notice poolId => rangeKey => whether range exists in _poolRangeKeys
    mapping(PoolId => mapping(bytes32 => bool)) private _rangeExists;

    /// @notice poolId => rangeKey => list of user addresses active in this range
    mapping(PoolId => mapping(bytes32 => address[])) public rangeUsers;

    /// @notice Authorized routers that can withdraw on behalf of users
    mapping(address => bool) public authorizedRouters;

    /// @notice Ephemeral scaled actual liquidity for the current swap (populated in preSwap, consumed in postSwap)
    /// poolId => rangeKey => user => actualLiquidity
    mapping(PoolId => mapping(bytes32 => mapping(address => uint128)))
        public ephemeralScaledLiquidity;

    // ─── Events ──────────────────────────────────────────────────────────────

    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event PositionAdded(
        address indexed user,
        bytes32 indexed positionId,
        PoolId indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    );
    event PositionRemoved(
        address indexed user,
        bytes32 indexed positionId,
        PoolId indexed poolId
    );
    event FeesClaimed(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event SwapSettled(address indexed token, int256 delta);

    // ─── Errors ──────────────────────────────────────────────────────────────

    error ZeroAmount();
    error ZeroAddress();
    error InsufficientFreeBalance();
    error PositionNotFound();
    error PositionAlreadyExists();
    error InvalidTicks();
    error TransferFailed();
    error InvalidHookInterface();

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyHook() {
        bool isValid = false;
        try IAqua0BaseHookMarker(msg.sender).supportsInterface(type(IAqua0BaseHookMarker).interfaceId) returns (bool result) {
            isValid = result;
        } catch {
            isValid = false;
        }
        if (!isValid) revert InvalidHookInterface();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _owner) Ownable(_owner) {}

    receive() external payable {}

    // ─── Router Authorization ─────────────────────────────────────────────────

    function setAuthorizedRouter(address router, bool authorized) external onlyOwner {
        authorizedRouters[router] = authorized;
    }

    // ─── Internal Auth Helper ────────────────────────────────────────────────

    function _checkHookOrOwner(address owner) internal view {
        if (msg.sender == owner) return;
        if (authorizedRouters[msg.sender]) return;
        bool isValid = false;
        try IAqua0BaseHookMarker(msg.sender).supportsInterface(type(IAqua0BaseHookMarker).interfaceId) returns (bool result) {
            isValid = result;
        } catch {
            isValid = false;
        }
        if (!isValid) revert InvalidHookInterface();
    }

    // ─── User: Deposit / Withdraw ─────────────────────────────────────────────

    function deposit(address token, uint256 amount, address to) external nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        freeBalance[to][token] += amount;

        emit Deposited(to, token, amount);
    }

    /// @notice Deposit native ETH into the shared pool.
    function depositNative(address to) external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();

        freeBalance[to][address(0)] += msg.value;

        emit Deposited(to, address(0), msg.value);
    }

    function withdraw(address token, uint256 amount, address from, address to) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _checkHookOrOwner(from);

        if (freeBalance[from][token] < amount)
            revert InsufficientFreeBalance();

        freeBalance[from][token] -= amount;

        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }

        emit Withdrawn(from, token, amount);
    }

    /// @notice Claim accumulated fees for a specific token
    function claimFees(address token, address from, address to) external nonReentrant {
        _checkHookOrOwner(from);
        
        uint256 amount = earnedFees[from][token];
        if (amount == 0) revert ZeroAmount();

        earnedFees[from][token] = 0;

        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }

        emit FeesClaimed(from, token, amount);
    }

    // ─── User: Positions ─────────────────────────────────────────────────────

    /// @notice Allocate liquidity from free balance into a specific V4 pool + tick range.
    ///         The amount of tokens "locked" is implicit - tokens stay in this contract,
    ///         only the liquidityShares counter increases. The user is responsible for
    ///         ensuring their free token balances cover the position's value.
    /// @param key          The V4 PoolKey for the target pool
    /// @param tickLower    The lower tick bound (must be multiple of pool's tickSpacing)
    /// @param tickUpper    The upper tick bound (must be tickLower < tickUpper)
    /// @param liquidity    The amount of V4 liquidity units to allocate
    /// @param token0Amount Amount of token0 to reserve for this position
    /// @param token1Amount Amount of token1 to reserve for this position
    /// @return positionId  The unique ID for this user's position
    function addPosition(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 token0Amount,
        uint256 token1Amount,
        address owner
    ) external nonReentrant returns (bytes32 positionId) {
        _checkHookOrOwner(owner);

        if (tickLower >= tickUpper) revert InvalidTicks();
        if (liquidity == 0) revert ZeroAmount();

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        // Check but DO NOT lock free balances (true liquidity amplification)
        if (token0Amount > 0) {
            if (freeBalance[owner][token0] < token0Amount)
                revert InsufficientFreeBalance();
        }
        if (token1Amount > 0) {
            if (freeBalance[owner][token1] < token1Amount)
                revert InsufficientFreeBalance();
        }

        PoolId poolId = key.toId();
        positionId = _positionId(owner, poolId, tickLower, tickUpper);

        if (userPositions[owner][positionId].active) {
            // Accumulate into existing position
            userPositions[owner][positionId].liquidityShares += liquidity;
            userPositions[owner][positionId].token0Initial += token0Amount;
            userPositions[owner][positionId].token1Initial += token1Amount;
        } else {
            // Store new user position
            userPositions[owner][positionId] = UserPosition({
                poolId: poolId,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityShares: liquidity,
                token0Initial: token0Amount,
                token1Initial: token1Amount,
                active: true
            });
            _userPositionIds[owner].push(positionId);
        }

        // Update aggregated range
        bytes32 rangeKey = _rangeKey(tickLower, tickUpper);
        if (!_rangeExists[poolId][rangeKey]) {
            _rangeExists[poolId][rangeKey] = true;
            _poolRangeKeys[poolId].push(rangeKey);
            aggregatedRanges[poolId][rangeKey] = RangeInfo({
                tickLower: tickLower,
                tickUpper: tickUpper,
                totalLiquidity: liquidity
            });
        } else {
            aggregatedRanges[poolId][rangeKey].totalLiquidity += liquidity;
        }

        // Track user in range
        bool foundUser = false;
        address[] memory users = rangeUsers[poolId][rangeKey];
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == owner) {
                foundUser = true;
                break;
            }
        }
        if (!foundUser) {
            rangeUsers[poolId][rangeKey].push(owner);
        }

        emit PositionAdded(
            owner,
            positionId,
            poolId,
            tickLower,
            tickUpper,
            liquidity
        );
    }

    /// @notice Remove a virtual position, returning reserved tokens to free balance.
    /// @param key         The V4 PoolKey
    /// @param tickLower   The lower tick of the position to remove
    /// @param tickUpper   The upper tick of the position to remove
    function removePosition(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        address owner
    ) external nonReentrant {
        _checkHookOrOwner(owner);

        PoolId poolId = key.toId();
        bytes32 positionId = _positionId(
            owner,
            poolId,
            tickLower,
            tickUpper
        );

        UserPosition storage pos = userPositions[owner][positionId];
        if (!pos.active) revert PositionNotFound();

        uint128 liquidity = pos.liquidityShares;

        // Deactivate user position
        // Deactivate user position
        pos.active = false;
        pos.liquidityShares = 0;

        pos.token0Initial = 0;
        pos.token1Initial = 0;

        // Update aggregated range
        bytes32 rangeKey = _rangeKey(tickLower, tickUpper);
        aggregatedRanges[poolId][rangeKey].totalLiquidity -= liquidity;

        emit PositionRemoved(owner, positionId, poolId);
    }

    // ─── Hook: Aggregation + Settlement ──────────────────────────────────────

    /// @notice Returns the dynamically scaled active tick ranges for the swap
    ///         Checks each user's real-time free balance and scales their virtual liability to match their capacity.
    function preSwap(
        PoolKey calldata key
    ) external onlyHook returns (RangeInfo[] memory ranges) {
        PoolId poolId = key.toId();
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        bytes32[] storage rangeKeys = _poolRangeKeys[poolId];
        uint256 count = rangeKeys.length;

        // Pre-count active ranges
        uint256 activeCount;
        for (uint256 i = 0; i < count; i++) {
            if (aggregatedRanges[poolId][rangeKeys[i]].totalLiquidity > 0) {
                activeCount++;
            }
        }

        ranges = new RangeInfo[](activeCount);
        uint256 idx;

        for (uint256 i = 0; i < count; i++) {
            RangeInfo storage r = aggregatedRanges[poolId][rangeKeys[i]];
            if (r.totalLiquidity == 0) continue;

            bytes32 rangeKey = rangeKeys[i];
            uint128 totalScaledLiquidity = _computeRangeScaledLiquidity(
                poolId, rangeKey, r.tickLower, r.tickUpper, token0, token1
            );

            ranges[idx] = RangeInfo({
                tickLower: r.tickLower,
                tickUpper: r.tickUpper,
                totalLiquidity: totalScaledLiquidity
            });
            idx++;
        }
    }

    /// @dev Private helper to compute per-user scaled liquidity for a range, store it ephemerally, and return total.
    function _computeRangeScaledLiquidity(
        PoolId poolId,
        bytes32 rangeKey,
        int24 tickLower,
        int24 tickUpper,
        address token0,
        address token1
    ) private returns (uint128 totalScaledLiquidity) {
        address[] memory users = rangeUsers[poolId][rangeKey];
        for (uint256 j = 0; j < users.length; j++) {
            address user = users[j];
            bytes32 posId = _positionId(user, poolId, tickLower, tickUpper);
            UserPosition storage pos = userPositions[user][posId];

            if (!pos.active) continue;

            uint256 scale = 1e18;
            if (pos.token0Initial > 0) {
                uint256 s0 = (freeBalance[user][token0] * 1e18) / pos.token0Initial;
                if (s0 < scale) scale = s0;
            }
            if (pos.token1Initial > 0) {
                uint256 s1 = (freeBalance[user][token1] * 1e18) / pos.token1Initial;
                if (s1 < scale) scale = s1;
            }

            uint128 actualLiquidity = uint128(
                (uint256(pos.liquidityShares) * scale) / 1e18
            );
            ephemeralScaledLiquidity[poolId][rangeKey][user] = actualLiquidity;
            totalScaledLiquidity += actualLiquidity;
        }
    }

    /// @notice Takes the exact BalanceDeltas generated by the swap for each range, calculates Net PnL,
    ///         and distributes it precisely to users based on their ephemeral actual liquidity contribution.
    /// @param lpFee The pool's active LP fee in pips (e.g. 3000 = 0.3%). Used to isolate earned fees from inventory shift.
    function postSwap(
        PoolKey calldata key,
        RangeInfo[] calldata injectedRanges,
        BalanceDelta[] calldata mintDeltas,
        BalanceDelta[] calldata burnDeltas,
        uint24 lpFee
    ) external onlyHook {
        PoolId poolId = key.toId();
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        for (uint256 i = 0; i < injectedRanges.length; i++) {
            RangeInfo calldata r = injectedRanges[i];
            bytes32 rangeKey = _rangeKey(r.tickLower, r.tickUpper);
            uint128 totalActualLiquidity = r.totalLiquidity;

            if (totalActualLiquidity == 0) continue;

            // netPnL = mint (cost to add) + burn (tokens returned + fees)
            int256 netPnL0 = int256(
                BalanceDeltaLibrary.amount0(mintDeltas[i])
            ) + int256(BalanceDeltaLibrary.amount0(burnDeltas[i]));
            int256 netPnL1 = int256(
                BalanceDeltaLibrary.amount1(mintDeltas[i])
            ) + int256(BalanceDeltaLibrary.amount1(burnDeltas[i]));

            address[] memory users = rangeUsers[poolId][rangeKey];

            for (uint256 j = 0; j < users.length; j++) {
                address user = users[j];
                uint128 userLiquidity = ephemeralScaledLiquidity[poolId][
                    rangeKey
                ][user];

                if (userLiquidity == 0) continue;

                // Distribute PnL directly to freeBalance
                int256 userPnL0 = (netPnL0 * int256(uint256(userLiquidity))) /
                    int256(uint256(totalActualLiquidity));
                int256 userPnL1 = (netPnL1 * int256(uint256(userLiquidity))) /
                    int256(uint256(totalActualLiquidity));

                _applyNetPnL(user, token0, userPnL0, lpFee);
                _applyNetPnL(user, token1, userPnL1, lpFee);

                // Zero out storage to refund gas
                ephemeralScaledLiquidity[poolId][rangeKey][user] = 0;
            }
        }
    }

    /// @dev Positive pnl = input token inflow. Split into:
    ///      - fee portion  = pnl * lpFee / 1_000_000  → earnedFees (claimable)
    ///      - inventory shift = remainder              → freeBalance (auto-rebalanced principal)
    /// @dev Negative pnl = output token outflow (pure inventory shift) → deducted from freeBalance.
    function _applyNetPnL(address user, address token, int256 pnl, uint24 lpFee) internal {
        if (pnl > 0) {
            uint256 totalPositive = uint256(pnl);
            // Fee is taken from amountIn by Uniswap, so our share of positive PnL contains
            // both the fee portion AND the inventory shift (principal rebalancing).
            uint256 feePortion = (totalPositive * uint256(lpFee)) / 1_000_000;
            uint256 inventoryShift = totalPositive - feePortion;

            earnedFees[user][token] += feePortion;
            freeBalance[user][token] += inventoryShift;
        } else if (pnl < 0) {
            // Negative PnL is purely inventory shift (output token paid out)
            uint256 loss = uint256(-pnl);
            if (freeBalance[user][token] < loss) {
                freeBalance[user][token] = 0; // guard against underflow in edge cases
            } else {
                freeBalance[user][token] -= loss;
            }
        }
    }

    /// @notice Called by Aqua0Hook in afterSwap to settle net token movements.
    ///         If delta > 0: hook owes us tokens - take from hook (hook must have approved).
    ///         If delta < 0: we owe tokens - transfer to hook for PoolManager settlement.
    /// @param token The token to settle
    /// @param delta Positive = we receive, negative = we send
    function settleSwapDelta(
        address token,
        int256 delta
    ) external payable nonReentrant onlyHook {
        if (delta == 0) return;

        console.log("\n[SharedLiquidityPool] settleSwapDelta");
        console.log("  token:              ", token);
        console.log(
            "  delta:              ",
            delta > 0 ? uint256(delta) : uint256(-delta),
            delta > 0 ? "(incoming +)" : "(outgoing -)"
        );
        console.log("  pool ETH balance:   ", address(this).balance, "wei");

        if (delta > 0) {
            // Hook is sending us tokens (we earned from swap)
            if (token == address(0)) {
                console.log("  -> Receiving ETH from hook via msg.value");
                require(msg.value == uint256(delta), "ETH amount mismatch");
            } else {
                console.log("  -> Pulling ERC20 from hook via transferFrom");
                IERC20(token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    uint256(delta)
                );
            }
        } else {
            // We owe tokens - send to hook so hook can settle with PoolManager
            uint256 owed = uint256(-delta);
            if (token == address(0)) {
                console.log("  -> Sending", owed, "wei ETH to hook", msg.sender);
                (bool success, ) = msg.sender.call{value: owed}("");
                if (!success) revert TransferFailed();
                console.log("  -> ETH sent OK");
            } else {
                console.log("  -> Sending", owed, "wei ERC20 to hook");
                IERC20(token).safeTransfer(msg.sender, owed);
            }
        }

        emit SwapSettled(token, delta);
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    /// @notice Get all position IDs for a user
    function getUserPositionIds(
        address user
    ) external view returns (bytes32[] memory) {
        return _userPositionIds[user];
    }

    /// @notice Get all active range keys for a pool
    function getPoolRangeKeys(
        PoolId poolId
    ) external view returns (bytes32[] memory) {
        return _poolRangeKeys[poolId];
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _positionId(
        address user,
        PoolId poolId,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, poolId, tickLower, tickUpper));
    }

    function _rangeKey(
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(tickLower, tickUpper));
    }
}
