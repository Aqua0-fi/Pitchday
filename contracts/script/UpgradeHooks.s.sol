// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/test/PoolSwapTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SharedLiquidityPool} from "../src/v4/SharedLiquidityPool.sol";
import {TranchesHook} from "../src/v4/tranches/TranchesHook.sol";
import {TranchesRouter} from "../src/v4/tranches/TranchesRouter.sol";
import {HookMiner} from "./HookMiner.sol";
import {IUnlockCallback} from "@uniswap/v4-core/interfaces/callback/IUnlockCallback.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/libraries/TransientStateLibrary.sol";

contract UpgradeCreate2Factory {
    function deploy(bytes32 salt, bytes memory initCode) external returns (address hook) {
        assembly {
            hook := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        require(hook != address(0), "CREATE2 failed");
    }
}

contract UpgradeSetupRouter is IUnlockCallback {
    using TransientStateLibrary for IPoolManager;
    IPoolManager public immutable manager;
    struct CallbackData { address sender; PoolKey key; ModifyLiquidityParams params; }
    CallbackData internal _cbData;
    constructor(IPoolManager _manager) { manager = _manager; }
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params) external {
        _cbData = CallbackData(msg.sender, key, params);
        manager.unlock(abi.encode(_cbData));
    }
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        CallbackData memory cbd = abi.decode(data, (CallbackData));
        manager.modifyLiquidity(cbd.key, cbd.params, "");
        int256 d0 = manager.currencyDelta(address(this), cbd.key.currency0);
        int256 d1 = manager.currencyDelta(address(this), cbd.key.currency1);
        if (d0 < 0) {
            manager.sync(cbd.key.currency0);
            IERC20(Currency.unwrap(cbd.key.currency0)).transferFrom(cbd.sender, address(manager), uint256(-d0));
            manager.settle();
        }
        if (d0 > 0) { manager.take(cbd.key.currency0, cbd.sender, uint256(d0)); }
        if (d1 < 0) {
            manager.sync(cbd.key.currency1);
            IERC20(Currency.unwrap(cbd.key.currency1)).transferFrom(cbd.sender, address(manager), uint256(-d1));
            manager.settle();
        }
        if (d1 > 0) { manager.take(cbd.key.currency1, cbd.sender, uint256(d1)); }
        return "";
    }
}

/// @title UpgradeHooks
/// @notice Fresh deploy of all hooks + routers + SharedPool + PoolSwapTest
///         Uses a unique nonce bump to avoid CreateCollision
contract UpgradeHooks is Script {
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant MUSDC = 0x73c56ddD816e356387Caf740c804bb9D379BE47E;
    address constant MWETH = 0x7fF28651365c735c22960E27C2aFA97AbE4Cf2Ad;

    uint160 constant TRANCHES_HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
    );

    uint160 constant SQRT_PRICE_2000 = 3543191142285914378072636784640;
    int256 constant SEED_LIQUIDITY = 100e18;

    struct PoolConfig {
        uint24 fee;
        int24 tickSpacing;
        string label;
    }

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        PoolConfig[3] memory pools = [
            PoolConfig({ fee: 500,   tickSpacing: 10,  label: "Conservative (0.05%)" }),
            PoolConfig({ fee: 3000,  tickSpacing: 60,  label: "Standard (0.30%)" }),
            PoolConfig({ fee: 10000, tickSpacing: 200, label: "Aggressive (1.00%)" })
        ];

        console.log("=== Upgrade: Fresh Deploy All ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // Deploy fresh infra
        UpgradeCreate2Factory factory = new UpgradeCreate2Factory();
        SharedLiquidityPool sharedPool = new SharedLiquidityPool(deployer);
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOL_MANAGER));
        UpgradeSetupRouter setupRouter = new UpgradeSetupRouter(IPoolManager(POOL_MANAGER));

        console.log("SharedLiquidityPool:", address(sharedPool));
        console.log("PoolSwapTest:", address(swapRouter));

        IERC20(MUSDC).approve(address(setupRouter), type(uint256).max);
        IERC20(MWETH).approve(address(setupRouter), type(uint256).max);

        Currency c0 = Currency.wrap(MUSDC);
        Currency c1 = Currency.wrap(MWETH);

        address[3] memory hookAddrs;
        address[3] memory routerAddrs;

        // Deploy 3 Aqua hooks + routers
        for (uint256 i = 0; i < 3; i++) {
            console.log("");
            console.log(string.concat("--- Pool ", vm.toString(i + 1), ": ", pools[i].label, " ---"));

            bytes memory hookInitCode = abi.encodePacked(
                type(TranchesHook).creationCode,
                abi.encode(IPoolManager(POOL_MANAGER), sharedPool, deployer)
            );

            (bytes32 salt, address expectedAddr) = HookMiner.find(
                address(factory), TRANCHES_HOOK_FLAGS, keccak256(hookInitCode), i * 100000
            );

            address hookAddr = factory.deploy(salt, hookInitCode);
            require(hookAddr == expectedAddr, "Hook mismatch");
            TranchesHook hook = TranchesHook(payable(hookAddr));
            console.log("  Hook:", hookAddr);

            TranchesRouter router = new TranchesRouter(IPoolManager(POOL_MANAGER), hook, sharedPool);
            hook.setTrustedRouter(address(router));
            sharedPool.setAuthorizedRouter(address(router), true);
            console.log("  Router:", address(router));

            PoolKey memory poolKey = PoolKey({ currency0: c0, currency1: c1, fee: pools[i].fee, tickSpacing: pools[i].tickSpacing, hooks: IHooks(hookAddr) });
            IPoolManager(POOL_MANAGER).initialize(poolKey, SQRT_PRICE_2000);

            setupRouter.modifyLiquidity(poolKey, ModifyLiquidityParams({
                tickLower: (int24(-887220) / pools[i].tickSpacing) * pools[i].tickSpacing,
                tickUpper: (int24(887220) / pools[i].tickSpacing) * pools[i].tickSpacing,
                liquidityDelta: SEED_LIQUIDITY,
                salt: bytes32(0)
            }));
            console.log("  Initialized + seeded");

            hookAddrs[i] = hookAddr;
            routerAddrs[i] = address(router);
        }

        // Traditional pool (isolated)
        console.log("");
        console.log("--- Pool 4: Traditional ---");

        SharedLiquidityPool isolatedPool = new SharedLiquidityPool(deployer);
        console.log("  IsolatedPool:", address(isolatedPool));

        bytes memory tradInitCode = abi.encodePacked(
            type(TranchesHook).creationCode,
            abi.encode(IPoolManager(POOL_MANAGER), isolatedPool, deployer)
        );
        (bytes32 tradSalt, address tradExpected) = HookMiner.find(
            address(factory), TRANCHES_HOOK_FLAGS, keccak256(tradInitCode), 500000
        );
        address tradHookAddr = factory.deploy(tradSalt, tradInitCode);
        require(tradHookAddr == tradExpected, "Trad hook mismatch");
        TranchesHook tradHook = TranchesHook(payable(tradHookAddr));
        console.log("  Hook:", tradHookAddr);

        TranchesRouter tradRouter = new TranchesRouter(IPoolManager(POOL_MANAGER), tradHook, isolatedPool);
        tradHook.setTrustedRouter(address(tradRouter));
        isolatedPool.setAuthorizedRouter(address(tradRouter), true);
        console.log("  Router:", address(tradRouter));

        PoolKey memory tradKey = PoolKey({ currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(tradHookAddr) });
        IPoolManager(POOL_MANAGER).initialize(tradKey, SQRT_PRICE_2000);
        setupRouter.modifyLiquidity(tradKey, ModifyLiquidityParams({
            tickLower: (int24(-887220) / int24(60)) * int24(60),
            tickUpper: (int24(887220) / int24(60)) * int24(60),
            liquidityDelta: SEED_LIQUIDITY,
            salt: bytes32(0)
        }));
        console.log("  Initialized + seeded");

        vm.stopBroadcast();

        // Write JSON
        string memory json = string.concat(
            '{\n  "chainId": 1301,\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "poolManager": "', vm.toString(POOL_MANAGER), '",\n',
            '  "sharedLiquidityPool": "', vm.toString(address(sharedPool)), '",\n',
            '  "swapRouter": "', vm.toString(address(swapRouter)), '",\n',
            '  "currency0": "', vm.toString(MUSDC), '",\n',
            '  "currency1": "', vm.toString(MWETH), '",\n'
        );
        json = string.concat(json,
            '  "pools": [\n',
            '    { "label": "Conservative", "fee": 500, "tickSpacing": 10, "hook": "', vm.toString(hookAddrs[0]), '", "router": "', vm.toString(routerAddrs[0]), '", "aqua": true },\n',
            '    { "label": "Standard", "fee": 3000, "tickSpacing": 60, "hook": "', vm.toString(hookAddrs[1]), '", "router": "', vm.toString(routerAddrs[1]), '", "aqua": true },\n',
            '    { "label": "Aggressive", "fee": 10000, "tickSpacing": 200, "hook": "', vm.toString(hookAddrs[2]), '", "router": "', vm.toString(routerAddrs[2]), '", "aqua": true },\n'
        );
        json = string.concat(json,
            '    { "label": "Traditional", "fee": 3000, "tickSpacing": 60, "hook": "', vm.toString(tradHookAddr), '", "router": "', vm.toString(address(tradRouter)), '", "aqua": false, "isolatedPool": "', vm.toString(address(isolatedPool)), '" }\n',
            '  ]\n}'
        );
        vm.writeFile("deployments/v4-tranches-unichain-sepolia.json", json);
        console.log("\nSaved to deployments/v4-tranches-unichain-sepolia.json");
    }
}
