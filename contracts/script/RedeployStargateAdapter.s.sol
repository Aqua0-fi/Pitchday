// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../src/bridge/BridgeRegistry.sol";
import "../src/bridge/StargateAdapter.sol";

/// @title RedeployStargateAdapter
/// @author Aqua0 Team
/// @notice Redeploys StargateAdapter and swaps it in BridgeRegistry on Base or Unichain.
/// @dev Reads old stargateAdapter + bridgeRegistry addresses from deployments/<chain>.json,
///      deploys a new StargateAdapter (with native ETH pool fix), registers the WETH→pool mapping,
///      updates BridgeRegistry, and patches the JSON with the new address.
///
///      Usage (via bash wrapper):
///        CHAIN=base DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-stargate-adapter.sh
///        CHAIN=unichain DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-stargate-adapter.sh
contract RedeployStargateAdapter is Script {
    // ── Shared addresses ──────────────────────────────────────────────────────
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // ── Chain-specific Stargate ETH pools ──────────────────────────────────────
    address constant STARGATE_ETH_BASE = 0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7;
    address constant STARGATE_ETH_UNICHAIN = 0xe9aBA835f813ca05E50A6C0ce65D0D74390F7dE7;

    // ── Chain IDs ─────────────────────────────────────────────────────────────
    uint256 constant BASE_CHAIN_ID = 8453;
    uint256 constant UNICHAIN_CHAIN_ID = 130;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Detect chain
        address stargateEth;
        string memory chainName;

        if (block.chainid == BASE_CHAIN_ID) {
            stargateEth = STARGATE_ETH_BASE;
            chainName = "base";
        } else if (block.chainid == UNICHAIN_CHAIN_ID) {
            stargateEth = STARGATE_ETH_UNICHAIN;
            chainName = "unichain";
        } else {
            revert("RedeployStargateAdapter: unsupported chain");
        }

        // Read existing deployment addresses from JSON
        string memory jsonPath = string.concat("./deployments/", chainName, ".json");
        string memory jsonData = vm.readFile(jsonPath);

        address oldAdapter = vm.parseJsonAddress(jsonData, ".stargateAdapter");
        address registryAddr = vm.parseJsonAddress(jsonData, ".bridgeRegistry");

        console.log("Chain:                ", chainName);
        console.log("Deployer:             ", deployer);
        console.log("Old StargateAdapter:  ", oldAdapter);
        console.log("BridgeRegistry:       ", registryAddr);
        console.log("Stargate ETH Pool:    ", stargateEth);

        BridgeRegistry registry = BridgeRegistry(registryAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy new StargateAdapter (with native ETH pool fix)
        StargateAdapter newAdapter = new StargateAdapter(deployer);
        console.log("New StargateAdapter:  ", address(newAdapter));

        // 2. Register WETH → Stargate ETH pool mapping on new adapter
        newAdapter.registerPool(WETH, stargateEth);

        // 3. Update BridgeRegistry to point STARGATE key to new adapter
        bytes32 stargateKey = keccak256("STARGATE");
        registry.setAdapter(stargateKey, address(newAdapter));

        vm.stopBroadcast();

        // 4. Patch deployment JSON with new StargateAdapter address
        vm.writeJson(vm.toString(address(newAdapter)), jsonPath, ".stargateAdapter");

        console.log("");
        console.log("Done! Updated", jsonPath);
    }
}
