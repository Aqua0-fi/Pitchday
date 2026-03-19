// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";
import "../src/lp/AccountFactory.sol";
import {Account as LPAccount} from "../src/lp/Account.sol";
import "../src/rebalancer/Rebalancer.sol";
import "../src/bridge/StargateAdapter.sol";
import "../src/bridge/Composer.sol";
import "../src/bridge/BridgeRegistry.sol";
import "../src/bridge/CCTPAdapter.sol";
import "../src/bridge/CCTPComposer.sol";
import "../src/aqua/AquaAdapter.sol";
import {ICreateX} from "../src/interface/ICreateX.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployTestnetV2
/// @notice Full deployment of all Aqua0 contracts to Base Sepolia or Unichain Sepolia.
///         Mirrors Deploy.s.sol but uses testnet-specific addresses for Aqua, SwapVMRouter,
///         LZ Endpoint, and Stargate (which aren't on testnets from the protocol team).
///
/// Usage:
///   Base Sepolia:
///     DEPLOYER_PRIVATE_KEY=0x... forge script script/DeployTestnetV2.s.sol \
///       --rpc-url https://sepolia.base.org --broadcast -vvv
///
///   Unichain Sepolia:
///     DEPLOYER_PRIVATE_KEY=0x... forge script script/DeployTestnetV2.s.sol \
///       --rpc-url https://unichain-sepolia-rpc.publicnode.com --broadcast -vvv
contract DeployTestnetV2 is Script {
    // ── Shared (same on all EVM chains) ─────────────────────────────────────
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    // CCTP V2 — same on Base Sepolia and Unichain Sepolia
    address constant TOKEN_MESSENGER_V2 =
        0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address constant MESSAGE_TRANSMITTER_V2 =
        0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    // ── Base Sepolia (84532) ─────────────────────────────────────────────────
    // AquaRouter + SwapVMRouter deployed by us (temp/aqua, temp/swap-vm)
    address constant AQUA_BASE_SEPOLIA =
        0x8D341ff509B00fD894A39Dc0f25E0A20b8d7049F;
    address constant SWAP_VM_ROUTER_BASE_SEPOLIA =
        0x48feDe1F1968CB2C2F1B7525f7023f13F47f4D87;
    address constant LZ_ENDPOINT_BASE_SEPOLIA =
        0x6EDCE65403992e310A62460808c4b910D972f10f;
    // Stargate not on Base Sepolia — using address(1) as placeholder
    address constant STARGATE_ETH_BASE_SEPOLIA = address(0x1);

    // ── Unichain Sepolia (1301) ──────────────────────────────────────────────
    address constant AQUA_UNICHAIN_SEPOLIA =
        0x42484731fd3DB1DA859ef98bF7527Aa914d0257A;
    address constant SWAP_VM_ROUTER_UNICHAIN_SEPOLIA =
        0x0C1fa25C8A5177A4b4B09478D2Bd69ebd62160aF;
    address constant LZ_ENDPOINT_UNICHAIN_SEPOLIA =
        0xb8815f3f882614048CbE201a67eF9c6F10fe5035;
    // Stargate not on Unichain Sepolia — using address(1) as placeholder
    address constant STARGATE_ETH_UNICHAIN_SEPOLIA = address(0x1);

    // ── Chain IDs ────────────────────────────────────────────────────────────
    uint256 constant BASE_SEPOLIA_ID = 84532;
    uint256 constant UNICHAIN_SEPOLIA_ID = 1301;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Resolve per-chain values
        address aqua;
        address swapVMRouter;
        address lzEndpoint;
        address stargateEth;
        string memory chainName;

        if (block.chainid == BASE_SEPOLIA_ID) {
            aqua = AQUA_BASE_SEPOLIA;
            swapVMRouter = SWAP_VM_ROUTER_BASE_SEPOLIA;
            lzEndpoint = LZ_ENDPOINT_BASE_SEPOLIA;
            stargateEth = STARGATE_ETH_BASE_SEPOLIA;
            chainName = "base-sepolia";
        } else if (block.chainid == UNICHAIN_SEPOLIA_ID) {
            aqua = AQUA_UNICHAIN_SEPOLIA;
            swapVMRouter = SWAP_VM_ROUTER_UNICHAIN_SEPOLIA;
            lzEndpoint = LZ_ENDPOINT_UNICHAIN_SEPOLIA;
            stargateEth = STARGATE_ETH_UNICHAIN_SEPOLIA;
            chainName = "unichain-sepolia";
        } else {
            revert(
                string.concat(
                    "DeployTestnetV2: unsupported chainId - ",
                    vm.toString(block.chainid)
                )
            );
        }

        console.log("=== Aqua0 Full Testnet Deployment (V2) ===");
        console.log("Chain:      ", chainName);
        console.log("ChainId:    ", block.chainid);
        console.log("Deployer:   ", deployer);
        console.log("Balance:    ", deployer.balance / 1e15, "mETH");
        console.log("");

        vm.startBroadcast(deployerKey);

        // Phase 1 — Infrastructure

        // 1. BridgeRegistry
        BridgeRegistry bridgeRegistry = new BridgeRegistry(deployer);
        console.log("BridgeRegistry:   ", address(bridgeRegistry));

        // 2. CCTPAdapter
        CCTPAdapter cctpAdapter = new CCTPAdapter(TOKEN_MESSENGER_V2, deployer);
        console.log("CCTPAdapter:      ", address(cctpAdapter));

        // 3. CCTPComposer
        // Note: usdc placeholder (address(1)) — no testnet USDC contract required at deploy time
        CCTPComposer cctpComposer = new CCTPComposer(
            MESSAGE_TRANSMITTER_V2,
            WETH,
            deployer
        );
        console.log("CCTPComposer:     ", address(cctpComposer));

        // 4. StargateAdapter (multi-asset)
        StargateAdapter stargateAdapter = new StargateAdapter(deployer);
        if (stargateEth != address(0x1)) {
            stargateAdapter.registerPool(WETH, stargateEth);
        }
        console.log("StargateAdapter:  ", address(stargateAdapter));

        // 5. Composer (LZ)
        Composer composer = new Composer(lzEndpoint, deployer);
        if (stargateEth != address(0x1)) {
            composer.registerPool(stargateEth, WETH);
        }
        composer.setWeth(WETH);
        console.log("Composer:         ", address(composer));

        // Phase 2 — Configure BridgeRegistry
        bridgeRegistry.setAdapter(
            keccak256("STARGATE"),
            address(stargateAdapter)
        );
        bridgeRegistry.setAdapter(keccak256("CCTP"), address(cctpAdapter));
        bridgeRegistry.addComposer(address(composer));
        bridgeRegistry.addComposer(address(cctpComposer));

        // Phase 3 — Core contracts

        // 8. Account implementation (with BRIDGE_REGISTRY immutable)
        LPAccount accountImpl = new LPAccount(address(bridgeRegistry));
        console.log("LPAccount impl:   ", address(accountImpl));

        // 9. AccountFactory via CREATE3
        string memory factoryVersion = vm.envOr(
            "FACTORY_VERSION",
            string("v1-testnet")
        );
        console.log("Factory version:  ", factoryVersion);
        bytes32 factorySalt = bytes32(
            abi.encodePacked(
                deployer,
                bytes1(0x00),
                bytes11(
                    keccak256(
                        bytes(
                            string.concat(
                                "aqua0.account-factory.",
                                factoryVersion
                            )
                        )
                    )
                )
            )
        );
        bytes memory factoryInitCode = abi.encodePacked(
            type(AccountFactory).creationCode,
            abi.encode(
                aqua,
                swapVMRouter,
                CREATEX,
                address(accountImpl),
                deployer
            )
        );
        AccountFactory factory = AccountFactory(
            ICreateX(CREATEX).deployCreate3(factorySalt, factoryInitCode)
        );
        console.log("AccountFactory:   ", address(factory));
        console.log("  Beacon:         ", address(factory.BEACON()));

        // 10. Rebalancer
        Rebalancer rebalancerImpl = new Rebalancer();
        ERC1967Proxy rebalancerProxy = new ERC1967Proxy(
            address(rebalancerImpl),
            abi.encodeCall(Rebalancer.initialize, (deployer))
        );
        Rebalancer rebalancer = Rebalancer(address(rebalancerProxy));
        console.log("Rebalancer impl:  ", address(rebalancerImpl));
        console.log("Rebalancer proxy: ", address(rebalancer));

        // 11. AquaAdapter
        AquaAdapter aquaAdapter = new AquaAdapter(aqua);
        console.log("AquaAdapter:      ", address(aquaAdapter));

        vm.stopBroadcast();

        _writeJson(
            chainName,
            deployer,
            lzEndpoint,
            stargateEth,
            aqua,
            swapVMRouter,
            accountImpl,
            factory,
            rebalancerImpl,
            rebalancer,
            stargateAdapter,
            composer,
            aquaAdapter,
            bridgeRegistry,
            cctpAdapter,
            cctpComposer
        );

        console.log("");
        console.log("=== Deployment complete! ===");
        console.log("Written to: deployments/", chainName, ".json");
    }

    function _writeJson(
        string memory chainName,
        address deployer,
        address lzEndpoint,
        address stargateEth,
        address aqua,
        address swapVMRouter,
        LPAccount accountImpl,
        AccountFactory factory,
        Rebalancer rebalancerImpl,
        Rebalancer rebalancer,
        StargateAdapter stargateAdapter,
        Composer composer,
        AquaAdapter aquaAdapter,
        BridgeRegistry bridgeRegistry,
        CCTPAdapter cctpAdapter,
        CCTPComposer cctpComposer
    ) internal {
        string memory obj = "deploy";
        vm.serializeString(obj, "chain", chainName);
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeAddress(obj, "weth", WETH);
        vm.serializeAddress(obj, "lzEndpoint", lzEndpoint);
        vm.serializeAddress(obj, "stargateEth", stargateEth);
        vm.serializeAddress(obj, "aqua", aqua);
        vm.serializeAddress(obj, "swapVMRouter", swapVMRouter);
        vm.serializeAddress(obj, "createX", CREATEX);
        vm.serializeAddress(obj, "tokenMessengerV2", TOKEN_MESSENGER_V2);
        vm.serializeAddress(
            obj,
            "messageTransmitterV2",
            MESSAGE_TRANSMITTER_V2
        );
        vm.serializeAddress(obj, "accountImpl", address(accountImpl));
        vm.serializeAddress(obj, "beacon", address(factory.BEACON()));
        vm.serializeAddress(obj, "accountFactory", address(factory));
        vm.serializeAddress(obj, "rebalancerImpl", address(rebalancerImpl));
        vm.serializeAddress(obj, "rebalancer", address(rebalancer));
        vm.serializeAddress(obj, "stargateAdapter", address(stargateAdapter));
        vm.serializeAddress(obj, "composer", address(composer));
        vm.serializeAddress(obj, "bridgeRegistry", address(bridgeRegistry));
        vm.serializeAddress(obj, "cctpAdapter", address(cctpAdapter));
        vm.serializeAddress(obj, "cctpComposer", address(cctpComposer));
        string memory json = vm.serializeAddress(
            obj,
            "aquaAdapter",
            address(aquaAdapter)
        );

        string memory path = string.concat(
            "./deployments/",
            chainName,
            ".json"
        );
        vm.writeJson(json, path);
    }
}
