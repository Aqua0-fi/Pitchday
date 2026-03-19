// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "./DeployBase.s.sol";
import "../src/lp/AccountFactory.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import "../src/rebalancer/Rebalancer.sol";
import "../src/bridge/StargateAdapter.sol";
import "../src/bridge/Composer.sol";
import "../src/bridge/BridgeRegistry.sol";
import "../src/bridge/CCTPAdapter.sol";
import "../src/bridge/CCTPComposer.sol";
import "../src/aqua/AquaAdapter.sol";
import { ICreateX } from "../src/interface/ICreateX.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy
/// @author Aqua0 Team
/// @notice Production deployment script for Aqua0 contracts on Base and Unichain.
/// @dev Auto-detects chain via block.chainid (8453 = Base, 130 = Unichain).
///      Deployer key is loaded from DEPLOYER_PRIVATE_KEY env var.
///      Writes deployed addresses to deployments/<chain>.json.
contract Deploy is DeployBase {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Detect chain and set per-chain addresses
        address lzEndpoint;
        address stargateEth;
        address usdc;
        string memory chainName;

        if (block.chainid == BASE_CHAIN_ID) {
            lzEndpoint = LZ_ENDPOINT_BASE;
            stargateEth = STARGATE_ETH_BASE;
            usdc = USDC_BASE;
            chainName = "base";
        } else if (block.chainid == UNICHAIN_CHAIN_ID) {
            lzEndpoint = LZ_ENDPOINT_UNICHAIN;
            stargateEth = STARGATE_ETH_UNICHAIN;
            usdc = USDC_UNICHAIN;
            chainName = "unichain";
        } else {
            revert("Deploy: unsupported chain");
        }

        vm.startBroadcast(deployerKey);

        // Phase 1 — Deploy infrastructure

        // 1. BridgeRegistry
        BridgeRegistry bridgeRegistry = new BridgeRegistry(deployer);

        // 2. CCTPAdapter
        CCTPAdapter cctpAdapter = new CCTPAdapter(TOKEN_MESSENGER_V2, deployer);

        // 3. CCTPComposer
        CCTPComposer cctpComposer = new CCTPComposer(MESSAGE_TRANSMITTER_V2, usdc, deployer);

        // 4. StargateAdapter (multi-asset: register chain-specific Stargate ETH pool)
        StargateAdapter stargateAdapter = new StargateAdapter(deployer);
        stargateAdapter.registerPool(WETH, stargateEth);

        // 5. Composer (LZ)
        Composer composer = new Composer(lzEndpoint, deployer);
        composer.registerPool(stargateEth, WETH);
        composer.setWeth(WETH);

        // Phase 2 — Configure BridgeRegistry

        // 6. Set adapters
        bridgeRegistry.setAdapter(keccak256("STARGATE"), address(stargateAdapter));
        bridgeRegistry.setAdapter(keccak256("CCTP"), address(cctpAdapter));

        // 7. Add trusted composers
        bridgeRegistry.addComposer(address(composer));
        bridgeRegistry.addComposer(address(cctpComposer));

        // Phase 3 — Deploy core contracts

        // 8. Account implementation (with BRIDGE_REGISTRY immutable)
        LPAccount accountImpl = new LPAccount(address(bridgeRegistry));

        // 9. AccountFactory via CREATE3 (deterministic address across chains)
        bytes32 factorySalt = _buildFactorySalt(deployer);
        bytes memory factoryInitCode = abi.encodePacked(
            type(AccountFactory).creationCode, abi.encode(AQUA, SWAP_VM_ROUTER, CREATEX, address(accountImpl), deployer)
        );
        AccountFactory factory = AccountFactory(ICreateX(CREATEX).deployCreate3(factorySalt, factoryInitCode));

        // 10. Rebalancer implementation (disables initializers in constructor)
        Rebalancer rebalancerImpl = new Rebalancer();

        // 11. ERC1967Proxy for Rebalancer with initialize(owner) calldata
        ERC1967Proxy rebalancerProxy =
            new ERC1967Proxy(address(rebalancerImpl), abi.encodeCall(Rebalancer.initialize, (deployer)));
        Rebalancer rebalancer = Rebalancer(address(rebalancerProxy));

        // 12. AquaAdapter
        AquaAdapter aquaAdapter = new AquaAdapter(AQUA);

        vm.stopBroadcast();

        // Write deployment addresses to JSON
        _writeJson(
            chainName,
            deployer,
            lzEndpoint,
            accountImpl,
            factory,
            rebalancerImpl,
            rebalancer,
            stargateAdapter,
            composer,
            aquaAdapter,
            bridgeRegistry,
            cctpAdapter,
            cctpComposer,
            stargateEth,
            usdc
        );
    }

    function _writeJson(
        string memory chainName,
        address deployer,
        address lzEndpoint,
        LPAccount accountImpl,
        AccountFactory factory,
        Rebalancer rebalancerImpl,
        Rebalancer rebalancer,
        StargateAdapter stargateAdapter,
        Composer composer,
        AquaAdapter aquaAdapter,
        BridgeRegistry bridgeRegistry,
        CCTPAdapter cctpAdapter,
        CCTPComposer cctpComposer,
        address stargateEth,
        address usdc
    ) internal {
        string memory obj = "deploy";
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeAddress(obj, "aqua", AQUA);
        vm.serializeAddress(obj, "swapVMRouter", SWAP_VM_ROUTER);
        vm.serializeAddress(obj, "createX", CREATEX);
        vm.serializeAddress(obj, "lzEndpoint", lzEndpoint);
        vm.serializeAddress(obj, "weth", WETH);
        vm.serializeAddress(obj, "tokenMessengerV2", TOKEN_MESSENGER_V2);
        vm.serializeAddress(obj, "messageTransmitterV2", MESSAGE_TRANSMITTER_V2);
        vm.serializeAddress(obj, "stargateEth", stargateEth);
        vm.serializeAddress(obj, "usdc", usdc);
        vm.serializeAddress(obj, "accountImpl", address(accountImpl));
        vm.serializeAddress(obj, "accountFactory", address(factory));
        vm.serializeAddress(obj, "beacon", address(factory.BEACON()));
        vm.serializeAddress(obj, "rebalancerImpl", address(rebalancerImpl));
        vm.serializeAddress(obj, "rebalancer", address(rebalancer));
        vm.serializeAddress(obj, "stargateAdapter", address(stargateAdapter));
        vm.serializeAddress(obj, "composer", address(composer));
        vm.serializeAddress(obj, "bridgeRegistry", address(bridgeRegistry));
        vm.serializeAddress(obj, "cctpAdapter", address(cctpAdapter));
        vm.serializeAddress(obj, "cctpComposer", address(cctpComposer));
        string memory json = vm.serializeAddress(obj, "aquaAdapter", address(aquaAdapter));

        string memory path = string.concat("./deployments/", chainName, ".json");
        vm.writeJson(json, path);
    }
}
