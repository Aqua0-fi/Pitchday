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
    // 1 mWETH (token1) = 2000 mUSDC (token0) → price = 2000 → sqrtPriceX96 = sqrt(2000) * 2^96
    uint160 constant SQRT_PRICE_1_1 = 3543191142285914378072636784640;
    int256 constant SEED_LIQUIDITY = 100e18;

    // ─── Pool configurations ─────────────────────────────────────────────────
    struct PoolConfig {
        uint24 fee;
        int24 tickSpacing;
        string label;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address poolManagerAddr = POOL_MANAGER_UNICHAIN_SEPOLIA;

        require(block.chainid == UNICHAIN_SEPOLIA_ID, "Must deploy on Unichain Sepolia (1301)");

        // 3 pools with different fee tiers
        PoolConfig[3] memory pools = [
            PoolConfig({ fee: 500,   tickSpacing: 10,  label: "Conservative (0.05%)" }),
            PoolConfig({ fee: 3000,  tickSpacing: 60,  label: "Standard (0.30%)" }),
            PoolConfig({ fee: 10000, tickSpacing: 200, label: "Aggressive (1.00%)" })
        ];

        console.log("=== TrancheFi Multi-Pool Deployment ===");
        console.log("Chain:       Unichain Sepolia (1301)");
        console.log("Deployer:   ", deployer);
        console.log("PoolManager:", poolManagerAddr);
        console.log("Pools:       3 (0.05%, 0.30%, 1.00%)");
        console.log("");

        vm.startBroadcast(deployerKey);

        // ─── Phase 1: Shared infra ─────────────────────────────────────────────

        TranchesCreate2Factory factory = new TranchesCreate2Factory();
        console.log("CREATE2 Factory:", address(factory));

        SharedLiquidityPool sharedPool = new SharedLiquidityPool(deployer);
        console.log("SharedLiquidityPool:", address(sharedPool));

        // Tokens
        address t0 = MUSDC;
        address t1 = MWETH;
        require(t0 < t1, "Token order wrong");
        Currency currency0 = Currency.wrap(t0);
        Currency currency1 = Currency.wrap(t1);
        console.log("currency0 (mUSDC):", t0);
        console.log("currency1 (mWETH):", t1);

        // Setup router for seeding (shared across all pools)
        TranchesSetupRouter setupRouter = new TranchesSetupRouter(IPoolManager(poolManagerAddr));
        IERC20(t0).approve(address(setupRouter), type(uint256).max);
        IERC20(t1).approve(address(setupRouter), type(uint256).max);

        // Arrays to store deployed addresses
        address[3] memory hookAddrs;
        address[3] memory routerAddrs;

        // ─── Phase 2: Deploy 3 hooks + pools ───────────────────────────────────

        for (uint256 i = 0; i < 3; i++) {
            console.log("");
            console.log(string.concat("--- Pool ", vm.toString(i + 1), ": ", pools[i].label, " ---"));

            // Mine salt for this hook
            bytes memory hookInitCode = abi.encodePacked(
                type(TranchesHook).creationCode,
                abi.encode(IPoolManager(poolManagerAddr), sharedPool, deployer)
            );

            // Use different starting salt for each to avoid collisions
            (bytes32 salt, address expectedAddr) = HookMiner.find(
                address(factory), TRANCHES_HOOK_FLAGS, keccak256(hookInitCode), i * 100000
            );

            // Deploy hook
            address hookAddr = factory.deploy(salt, hookInitCode);
            require(hookAddr == expectedAddr, "Hook address mismatch");
            TranchesHook hook = TranchesHook(payable(hookAddr));
            console.log("  TranchesHook:", hookAddr);

            // Deploy router
            TranchesRouter router = new TranchesRouter(IPoolManager(poolManagerAddr), hook, sharedPool);
            hook.setTrustedRouter(address(router));
            sharedPool.setAuthorizedRouter(address(router), true);
            console.log("  TranchesRouter:", address(router));

            // Initialize pool with this fee tier
            PoolKey memory poolKey = PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: pools[i].fee,
                tickSpacing: pools[i].tickSpacing,
                hooks: IHooks(hookAddr)
            });

            IPoolManager(poolManagerAddr).initialize(poolKey, SQRT_PRICE_1_1);
            console.log("  Pool initialized");

            // Seed liquidity
            setupRouter.modifyLiquidity(
                poolKey,
                ModifyLiquidityParams({
                    tickLower: (int24(-887220) / pools[i].tickSpacing) * pools[i].tickSpacing,
                    tickUpper: (int24(887220) / pools[i].tickSpacing) * pools[i].tickSpacing,
                    liquidityDelta: SEED_LIQUIDITY,
                    salt: bytes32(0)
                })
            );
            console.log("  Seeded with base liquidity");

            hookAddrs[i] = hookAddr;
            routerAddrs[i] = address(router);
        }

        // ─── Phase 3: Deploy 4th hook (Traditional LP — isolated SharedPool) ──

        console.log("");
        console.log("--- Pool 4: Traditional LP (0.30% - No Aqua) ---");

        SharedLiquidityPool isolatedPool = new SharedLiquidityPool(deployer);
        console.log("  IsolatedPool:", address(isolatedPool));

        bytes memory tradInitCode = abi.encodePacked(
            type(TranchesHook).creationCode,
            abi.encode(IPoolManager(poolManagerAddr), isolatedPool, deployer)
        );

        (bytes32 tradSalt, address tradExpected) = HookMiner.find(
            address(factory), TRANCHES_HOOK_FLAGS, keccak256(tradInitCode), 500000
        );

        address tradHookAddr = factory.deploy(tradSalt, tradInitCode);
        require(tradHookAddr == tradExpected, "Traditional hook address mismatch");
        TranchesHook tradHook = TranchesHook(payable(tradHookAddr));
        console.log("  TranchesHook:", tradHookAddr);

        TranchesRouter tradRouter = new TranchesRouter(IPoolManager(poolManagerAddr), tradHook, isolatedPool);
        tradHook.setTrustedRouter(address(tradRouter));
        isolatedPool.setAuthorizedRouter(address(tradRouter), true);
        console.log("  TranchesRouter:", address(tradRouter));

        // Use 0.30% fee (same as Standard) for fair comparison
        PoolKey memory tradKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(tradHookAddr)
        });

        IPoolManager(poolManagerAddr).initialize(tradKey, SQRT_PRICE_1_1);
        console.log("  Pool initialized (0.30% - isolated)");

        setupRouter.modifyLiquidity(
            tradKey,
            ModifyLiquidityParams({
                tickLower: (int24(-887220) / int24(60)) * int24(60),
                tickUpper: (int24(887220) / int24(60)) * int24(60),
                liquidityDelta: SEED_LIQUIDITY,
                salt: bytes32(0)
            })
        );
        console.log("  Seeded with base liquidity");

        vm.stopBroadcast();

        // ─── Phase 4: Write deployment JSON ─────────────────────────────────────

        string memory deployments = string.concat(
            '{\n  "chainId": 1301,\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "poolManager": "', vm.toString(poolManagerAddr), '",\n',
            '  "sharedLiquidityPool": "', vm.toString(address(sharedPool)), '",\n',
            '  "currency0": "', vm.toString(t0), '",\n',
            '  "currency1": "', vm.toString(t1), '",\n'
        );

        deployments = string.concat(deployments,
            '  "pools": [\n',
            '    { "label": "Conservative", "fee": 500, "tickSpacing": 10, "hook": "', vm.toString(hookAddrs[0]), '", "router": "', vm.toString(routerAddrs[0]), '", "aqua": true },\n',
            '    { "label": "Standard", "fee": 3000, "tickSpacing": 60, "hook": "', vm.toString(hookAddrs[1]), '", "router": "', vm.toString(routerAddrs[1]), '", "aqua": true },\n',
            '    { "label": "Aggressive", "fee": 10000, "tickSpacing": 200, "hook": "', vm.toString(hookAddrs[2]), '", "router": "', vm.toString(routerAddrs[2]), '", "aqua": true },\n'
        );
        deployments = string.concat(deployments,
            '    { "label": "Traditional", "fee": 3000, "tickSpacing": 60, "hook": "', vm.toString(tradHookAddr), '", "router": "', vm.toString(address(tradRouter)), '", "aqua": false, "isolatedPool": "', vm.toString(address(isolatedPool)), '" }\n',
            '  ]\n}'
        );

        vm.writeFile("deployments/v4-tranches-unichain-sepolia.json", deployments);
        console.log("\nDeployment saved to deployments/v4-tranches-unichain-sepolia.json");
    }
}
