// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../src/bridge/BridgeRegistry.sol";
import "../src/bridge/Composer.sol";

/// @title RedeployComposer
/// @author Aqua0 Team
/// @notice Redeploys LZ Composer and swaps it in BridgeRegistry on Base or Unichain.
/// @dev Reads old composer + bridgeRegistry addresses from deployments/<chain>.json,
///      deploys a new Composer (with native ETH wrapping fix + chain-specific LZ endpoint),
///      registers the Stargate pool, sets WETH, removes old composer from BridgeRegistry,
///      adds new one, and patches the JSON with the new address.
///
///      Usage (via bash wrapper):
///        CHAIN=base DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-composer.sh
///        CHAIN=unichain DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-composer.sh
contract RedeployComposer is Script {
    // ── Shared addresses ──────────────────────────────────────────────────────
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // ── Chain-specific LZ endpoints ──────────────────────────────────────────
    address constant LZ_ENDPOINT_BASE = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant LZ_ENDPOINT_UNICHAIN = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;

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
        address lzEndpoint;
        address stargateEth;
        string memory chainName;

        if (block.chainid == BASE_CHAIN_ID) {
            lzEndpoint = LZ_ENDPOINT_BASE;
            stargateEth = STARGATE_ETH_BASE;
            chainName = "base";
        } else if (block.chainid == UNICHAIN_CHAIN_ID) {
            lzEndpoint = LZ_ENDPOINT_UNICHAIN;
            stargateEth = STARGATE_ETH_UNICHAIN;
            chainName = "unichain";
        } else {
            revert("RedeployComposer: unsupported chain");
        }

        // Read existing deployment addresses from JSON
        string memory jsonPath = string.concat("./deployments/", chainName, ".json");
        string memory jsonData = vm.readFile(jsonPath);

        address oldComposer = vm.parseJsonAddress(jsonData, ".composer");
        address registryAddr = vm.parseJsonAddress(jsonData, ".bridgeRegistry");

        console.log("Chain:              ", chainName);
        console.log("Deployer:           ", deployer);
        console.log("Old Composer:       ", oldComposer);
        console.log("BridgeRegistry:     ", registryAddr);
        console.log("LZ Endpoint:        ", lzEndpoint);
        console.log("Stargate ETH Pool:  ", stargateEth);

        BridgeRegistry registry = BridgeRegistry(registryAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy new Composer (with correct LZ endpoint + native ETH wrapping)
        Composer newComposer = new Composer(lzEndpoint, deployer);
        console.log("New Composer:       ", address(newComposer));

        // 2. Register Stargate pool → token mapping
        newComposer.registerPool(stargateEth, WETH);

        // 3. Set WETH for native ETH wrapping
        newComposer.setWeth(WETH);

        // 4. Remove old composer from BridgeRegistry
        registry.removeComposer(oldComposer);

        // 5. Add new composer to BridgeRegistry
        registry.addComposer(address(newComposer));

        vm.stopBroadcast();

        // 6. Patch deployment JSON with new Composer address
        vm.writeJson(vm.toString(address(newComposer)), jsonPath, ".composer");
        vm.writeJson(vm.toString(lzEndpoint), jsonPath, ".lzEndpoint");

        console.log("");
        console.log("Done! Updated", jsonPath);
    }
}
