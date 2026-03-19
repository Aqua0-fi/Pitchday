// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {SharedLiquidityPool} from "../src/v4/SharedLiquidityPool.sol";
import {Aqua0Hook} from "../src/v4/Aqua0Hook.sol";
import {HookMiner} from "./HookMiner.sol";
import {Aqua0QuoteHelper} from "../src/v4/Aqua0QuoteHelper.sol";

contract SimpleCreate2Factory {
    function deploy(
        bytes32 salt,
        bytes memory initCode
    ) external returns (address hook) {
        assembly {
            hook := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        require(hook != address(0), "CREATE2 failed");
    }
}

/// @title DeployV4Hookathon
/// @notice Deploys SharedLiquidityPool and Aqua0Hook to Base Sepolia,
///         Unichain Sepolia, or a local Anvil fork of Base Sepolia.
///
/// Usage:
///   Base Sepolia:
///     forge script script/DeployV4Hookathon.s.sol:DeployV4Hookathon \
///       --rpc-url https://sepolia.base.org \
///       --private-key $DEPLOYER_PRIVATE_KEY \
///       --broadcast -vvv
///
///   Unichain Sepolia:
///     forge script script/DeployV4Hookathon.s.sol:DeployV4Hookathon \
///       --rpc-url https://unichain-sepolia-rpc.publicnode.com \
///       --private-key $DEPLOYER_PRIVATE_KEY \
///       --broadcast -vvv
///
///   Local Anvil (fork Base Sepolia):
///     forge script script/DeployV4Hookathon.s.sol:DeployV4Hookathon \
///       --rpc-url http://localhost:8545 \
///       --private-key $DEPLOYER_PRIVATE_KEY \
///       --broadcast -vvv
///
/// Requires env: DEPLOYER_PRIVATE_KEY
contract DeployV4Hookathon is Script {
    // ─── Uniswap V4 PoolManager addresses ────────────────────────────────────
    // Source: https://docs.uniswap.org/contracts/v4/deployments
    address constant POOL_MANAGER_BASE_SEPOLIA =
        0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant POOL_MANAGER_UNICHAIN_SEPOLIA =
        0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    // ─── Chain IDs ────────────────────────────────────────────────────────────
    uint256 constant BASE_SEPOLIA_ID = 84532;
    uint256 constant UNICHAIN_SEPOLIA_ID = 1301;

    // ─── Hook permission flags ─────────────────────────────────────────────────
    // BEFORE_SWAP (1<<7) | AFTER_SWAP (1<<6) = 0xC0
    uint160 constant HOOK_FLAGS =
        uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // ── Resolve PoolManager address by chain ──────────────────────────────
        address poolManagerAddr;
        string memory chainName;

        if (block.chainid == BASE_SEPOLIA_ID) {
            poolManagerAddr = POOL_MANAGER_BASE_SEPOLIA;
            chainName = "base-sepolia";
        } else if (block.chainid == UNICHAIN_SEPOLIA_ID) {
            poolManagerAddr = POOL_MANAGER_UNICHAIN_SEPOLIA;
            chainName = "unichain-sepolia";
        } else if (block.chainid == 696969) {
            // Local Anvil forking Base Sepolia — PoolManager at same address in fork
            poolManagerAddr = POOL_MANAGER_BASE_SEPOLIA;
            chainName = "local";
        } else {
            revert(
                string.concat(
                    "DeployV4Hookathon: unsupported chainId ",
                    vm.toString(block.chainid)
                )
            );
        }

        console.log("=== Aqua0 V4 Hookathon Deployment ===");
        console.log("Chain:      ", chainName);
        console.log("ChainId:    ", block.chainid);
        console.log("Deployer:   ", deployer);
        console.log("PoolManager:", poolManagerAddr);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 0. Deploy our vanilla CREATE2 Factory to bypass Forge salt-hashing
        SimpleCreate2Factory factory = new SimpleCreate2Factory();
        console.log("SimpleCreate2Factory:", address(factory));

        // 1. Deploy SharedLiquidityPool (no special address requirements)
        SharedLiquidityPool sharedPool = new SharedLiquidityPool(deployer);
        console.log("SharedLiquidityPool:", address(sharedPool));

        // 2. Mine a valid hook address.
        bytes memory hookInitCode = abi.encodePacked(
            type(Aqua0Hook).creationCode,
            abi.encode(IPoolManager(poolManagerAddr), sharedPool, deployer)
        );

        (bytes32 salt, address expectedHookAddr) = HookMiner.find(
            address(factory), // The factory will be the caller for CREATE2
            HOOK_FLAGS,
            keccak256(hookInitCode),
            0
        );

        console.log("Hook salt (uint):", uint256(salt));
        console.log("Expected hook:   ", expectedHookAddr);

        // 3. Deploy hook using our vanilla factory
        address hookAddr = factory.deploy(salt, hookInitCode);
        require(hookAddr == expectedHookAddr, "Hook address mismatch");

        Aqua0Hook hook = Aqua0Hook(payable(expectedHookAddr));
        console.log("Aqua0Hook deployed:", address(hook));

        // 4. (Removed) Hooks are now dynamically authorized via ERC165 check if they inherit Aqua0BaseHook

        // 5. Deploy QuoteHelper
        Aqua0QuoteHelper quoteHelper = new Aqua0QuoteHelper(
            IPoolManager(poolManagerAddr),
            sharedPool
        );
        console.log("QuoteHelper deployed:", address(quoteHelper));

        vm.stopBroadcast();

        // 6. Write deployment addresses to JSON
        string memory deployments = string.concat(
            "{\n",
            '  "chainId": ',
            vm.toString(block.chainid),
            ",\n",
            '  "deployer": "',
            vm.toString(deployer),
            '",\n',
            '  "poolManager": "',
            vm.toString(poolManagerAddr),
            '",\n',
            '  "sharedLiquidityPool": "',
            vm.toString(address(sharedPool)),
            '",\n',
            '  "aqua0Hook": "',
            vm.toString(address(hook)),
            '",\n',
            '  "aqua0QuoteHelper": "',
            vm.toString(address(quoteHelper)),
            '",\n',
            '  "hookSalt": "',
            vm.toString(salt),
            '"\n',
            "}"
        );

        string memory outPath = string.concat(
            "deployments/v4-hookathon-",
            chainName,
            ".json"
        );
        vm.writeFile(outPath, deployments);
        console.log("\nDeployment saved to:", outPath);
    }
}
