// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../src/bridge/BridgeRegistry.sol";
import "../src/bridge/CCTPComposer.sol";

/// @title RedeployCCTPComposer
/// @author Aqua0 Team
/// @notice Redeploys CCTPComposer and swaps it in BridgeRegistry on Base or Unichain.
/// @dev Reads old cctpComposer + bridgeRegistry addresses from deployments/<chain>.json,
///      deploys a new CCTPComposer, removes the old one from BridgeRegistry, adds the new one,
///      and patches the JSON with the new address.
///
///      Usage (via bash wrapper):
///        CHAIN=base DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-cctp-composer.sh
///        CHAIN=unichain DEPLOYER_PRIVATE_KEY=$KEY bash script/redeploy-cctp-composer.sh
contract RedeployCCTPComposer is Script {
    // ── Shared addresses ──────────────────────────────────────────────────────
    address constant MESSAGE_TRANSMITTER_V2 = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    // ── Chain-specific USDC ───────────────────────────────────────────────────
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_UNICHAIN = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;

    // ── Chain IDs ─────────────────────────────────────────────────────────────
    uint256 constant BASE_CHAIN_ID = 8453;
    uint256 constant UNICHAIN_CHAIN_ID = 130;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Detect chain
        address usdc;
        string memory chainName;

        if (block.chainid == BASE_CHAIN_ID) {
            usdc = USDC_BASE;
            chainName = "base";
        } else if (block.chainid == UNICHAIN_CHAIN_ID) {
            usdc = USDC_UNICHAIN;
            chainName = "unichain";
        } else {
            revert("RedeployCCTPComposer: unsupported chain");
        }

        // Read existing deployment addresses from JSON
        string memory jsonPath = string.concat("./deployments/", chainName, ".json");
        string memory jsonData = vm.readFile(jsonPath);

        address oldComposer = vm.parseJsonAddress(jsonData, ".cctpComposer");
        address registryAddr = vm.parseJsonAddress(jsonData, ".bridgeRegistry");

        console.log("Chain:              ", chainName);
        console.log("Deployer:           ", deployer);
        console.log("Old CCTPComposer:   ", oldComposer);
        console.log("BridgeRegistry:     ", registryAddr);

        BridgeRegistry registry = BridgeRegistry(registryAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy new CCTPComposer (with fixed CCTPMessageLib offset)
        CCTPComposer newComposer = new CCTPComposer(MESSAGE_TRANSMITTER_V2, usdc, deployer);
        console.log("New CCTPComposer:   ", address(newComposer));

        // 2. Remove old composer from BridgeRegistry
        registry.removeComposer(oldComposer);

        // 3. Add new composer to BridgeRegistry
        registry.addComposer(address(newComposer));

        vm.stopBroadcast();

        // 4. Patch deployment JSON with new CCTPComposer address
        vm.writeJson(vm.toString(address(newComposer)), jsonPath, ".cctpComposer");

        console.log("");
        console.log("Done! Updated", jsonPath);
    }
}
