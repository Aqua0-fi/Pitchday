// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {IUnlockCallback} from "@uniswap/v4-core/interfaces/callback/IUnlockCallback.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/libraries/TransientStateLibrary.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SharedLiquidityPool} from "../src/v4/SharedLiquidityPool.sol";
import {TranchesHook} from "../src/v4/tranches/TranchesHook.sol";
import {TranchesRouter} from "../src/v4/tranches/TranchesRouter.sol";
import {HookMiner} from "./HookMiner.sol";

// ─── Inline helpers (avoid pragma conflicts with v4-core test utils) ─────────

contract TranchesCreate2Factory {
    function deploy(bytes32 salt, bytes memory initCode) external returns (address hook) {
        assembly {
            hook := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        require(hook != address(0), "CREATE2 failed");
    }
}

contract TranchesSetupRouter is IUnlockCallback {
    using TransientStateLibrary for IPoolManager;

    IPoolManager public immutable manager;

    struct CallbackData {
        address sender;
        PoolKey key;
        ModifyLiquidityParams params;
    }

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params) external returns (BalanceDelta) {
        return abi.decode(manager.unlock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        (BalanceDelta delta,) = manager.modifyLiquidity(data.key, data.params, new bytes(0));

        int256 d0 = manager.currencyDelta(address(this), data.key.currency0);
        int256 d1 = manager.currencyDelta(address(this), data.key.currency1);

        if (d0 < 0) _settle(data.key.currency0, data.sender, uint256(-d0));
        if (d1 < 0) _settle(data.key.currency1, data.sender, uint256(-d1));
        if (d0 > 0) manager.take(data.key.currency0, data.sender, uint256(d0));
        if (d1 > 0) manager.take(data.key.currency1, data.sender, uint256(d1));

        return abi.encode(delta);
    }

    function _settle(Currency currency, address sender, uint256 amount) internal {
        manager.sync(currency);
        IERC20(Currency.unwrap(currency)).transferFrom(sender, address(manager), amount);
        manager.settle();
    }
}

contract MockTrancheToken is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 supply, address mintTo) ERC20(name_, symbol_) {
        _mint(mintTo, supply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ─── Main deploy script ─────────────────────────────────────────────────────

/// @title DeployTranches
/// @notice Deploys TranchesHook + TranchesRouter + mock tokens + initializes a pool
///         on Unichain Sepolia. Uses a dedicated SharedLiquidityPool for JIT.
///
/// Usage:
///   forge script script/DeployTranches.s.sol:DeployTranches \
///     --rpc-url https://sepolia.unichain.org \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast -vvv
contract DeployTranches is Script {
    // ─── Addresses ──────────────────────────────────────────────────────────────
    address constant POOL_MANAGER_UNICHAIN_SEPOLIA = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    uint256 constant UNICHAIN_SEPOLIA_ID = 1301;

    // ─── TranchesHook permission flags ──────────────────────────────────────────
    // afterInitialize | afterAddLiquidity | afterRemoveLiquidity | beforeSwap |
    // afterSwap | afterSwapReturnDelta | afterRemoveLiquidityReturnDelta
    uint160 constant TRANCHES_HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
    );

    // ─── Global Aqua0 Mock Tokens (Unichain Sepolia) ───────────────────────────
    // Use the team's shared mock tokens instead of deploying new ones.
    // currency0 must be the lower address per Uniswap V4 convention.
    address constant MUSDC = 0x73c56ddD816e356387Caf740c804bb9D379BE47E; // mUSDC (lower)
    address constant MWETH = 0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad; // mWETH (higher)

    // ─── Main Aqua0 SharedLiquidityPool (shared across all hooks) ────────────
    address constant SHARED_POOL = 0x3293BA3287C602411Bf371896BCba9C80e3a04FF;

    // ─── Pool parameters ────────────────────────────────────────────────────────
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 1:1 price
    int256 constant SEED_LIQUIDITY = 100e18;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address poolManagerAddr = POOL_MANAGER_UNICHAIN_SEPOLIA;

        require(block.chainid == UNICHAIN_SEPOLIA_ID, "Must deploy on Unichain Sepolia (1301)");

        console.log("=== TrancheFi Deployment ===");
        console.log("Chain:       Unichain Sepolia (1301)");
        console.log("Deployer:   ", deployer);
        console.log("PoolManager:", poolManagerAddr);
        console.log("Hook flags:  0x15C5");
        console.log("");

        vm.startBroadcast(deployerKey);

        // ─── Phase 1: Core contracts ────────────────────────────────────────────

        // 1. CREATE2 factory
        TranchesCreate2Factory factory = new TranchesCreate2Factory();
        console.log("CREATE2 Factory:", address(factory));

        // 2. Deploy our own SharedLiquidityPool (with PositionAlreadyExists fix + new interface)
        SharedLiquidityPool sharedPool = new SharedLiquidityPool(deployer);
        console.log("SharedLiquidityPool (own):", address(sharedPool));

        // 3. Mine hook salt
        bytes memory hookInitCode =
            abi.encodePacked(type(TranchesHook).creationCode, abi.encode(IPoolManager(poolManagerAddr), sharedPool, deployer));

        (bytes32 salt, address expectedAddr) =
            HookMiner.find(address(factory), TRANCHES_HOOK_FLAGS, keccak256(hookInitCode), 0);

        console.log("Hook salt:  ", uint256(salt));
        console.log("Expected:   ", expectedAddr);

        // 4. Deploy TranchesHook via CREATE2
        address hookAddr = factory.deploy(salt, hookInitCode);
        require(hookAddr == expectedAddr, "Hook address mismatch");
        TranchesHook hook = TranchesHook(payable(hookAddr));
        console.log("TranchesHook:", hookAddr);

        // 5. SharedLiquidityPool is permissionless (no onlyHook modifier)
        //    No registration needed — any hook can use it.
        console.log("SharedLiquidityPool is permissionless - no hook registration needed");

        // 6. Deploy TranchesRouter
        TranchesRouter tranchesRouter = new TranchesRouter(IPoolManager(poolManagerAddr), hook, sharedPool);
        console.log("TranchesRouter:", address(tranchesRouter));

        // 7. Set trusted router
        hook.setTrustedRouter(address(tranchesRouter));
        console.log("Router registered as trusted");

        // ─── Phase 2: Use global Aqua0 tokens + pool init ──────────────────────

        // 8. Use existing global mock tokens (mUSDC / mWETH)
        // Already sorted: MUSDC (0x73c5...) < MWETH (0x7fF2...)
        address t0 = MUSDC;
        address t1 = MWETH;
        require(t0 < t1, "Token order wrong");

        Currency currency0 = Currency.wrap(t0);
        Currency currency1 = Currency.wrap(t1);
        console.log("currency0 (mUSDC):", t0);
        console.log("currency1 (mWETH):", t1);

        // 9. Initialize pool
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });

        IPoolManager(poolManagerAddr).initialize(poolKey, SQRT_PRICE_1_1);
        console.log("Pool initialized (1:1 price, 0.3% fee)");

        // 10. Seed base liquidity
        TranchesSetupRouter setupRouter = new TranchesSetupRouter(IPoolManager(poolManagerAddr));

        IERC20(t0).approve(address(setupRouter), type(uint256).max);
        IERC20(t1).approve(address(setupRouter), type(uint256).max);

        setupRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -887220, // full range
                tickUpper: 887220,
                liquidityDelta: SEED_LIQUIDITY,
                salt: bytes32(0)
            })
        );
        console.log("Pool seeded with base liquidity");

        vm.stopBroadcast();

        // ─── Phase 3: Write deployment JSON ─────────────────────────────────────

        string memory deployments = string.concat(
            "{\n",
            '  "chainId": 1301,\n',
            '  "deployer": "',
            vm.toString(deployer),
            '",\n',
            '  "poolManager": "',
            vm.toString(poolManagerAddr),
            '",\n',
            '  "sharedLiquidityPool": "',
            vm.toString(address(sharedPool)),
            '",\n',
            '  "tranchesHook": "',
            vm.toString(hookAddr),
            '",\n',
            '  "tranchesRouter": "',
            vm.toString(address(tranchesRouter)),
            '",\n',
            '  "hookSalt": "',
            vm.toString(salt),
            '",\n',
            '  "currency0": "',
            vm.toString(t0),
            '",\n',
            '  "currency1": "',
            vm.toString(t1),
            '",\n',
            '  "poolFee": 3000,\n',
            '  "poolTickSpacing": 60\n',
            "}"
        );

        vm.writeFile("deployments/v4-tranches-unichain-sepolia.json", deployments);
        console.log("\nDeployment saved to deployments/v4-tranches-unichain-sepolia.json");
    }
}
