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
import "../src/interface/ISwapVMRouter.sol";
import { IWETH } from "../src/interface/IWETH.sol";
import "../test/utils/SwapVMProgramHelper.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title DeployLocal
/// @author Aqua0 Team
/// @notice Deploys all Aqua0 contracts to a local Anvil fork of Base or Unichain mainnet,
///         ships a sample strategy, and funds a swapper account — ready for LP + swap testing.
/// @dev Detects chain via block.chainid (8453 = Base, 130 = Unichain) and uses
///      the correct per-chain addresses for Stargate and USDC.
///
///      After running, the environment is set up for two flows:
///        LP flow:      account has WETH + USDC, Aqua-approved, ship/dock ready
///        Swapper flow: WETH strategy is active, swapper funded + approved for SwapVM Router
contract DeployLocal is DeployBase {
    // ── Anvil default accounts ──────────────────────────────────────────────
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    address constant SWAPPER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant SWAPPER_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    // ── Funding amounts ─────────────────────────────────────────────────────
    uint256 constant ACCOUNT_WETH = 10 ether;
    uint256 constant STRATEGY_WETH = 5 ether; // half shipped, half available
    uint256 constant SWAPPER_WETH = 10 ether;

    // ── Deployment state (set in run, used across helpers) ───────────────────
    AccountFactory public factory;
    Rebalancer public rebalancer;
    StargateAdapter public stargateAdapter;
    Composer public composer;
    BridgeRegistry public bridgeRegistry;
    CCTPAdapter public cctpAdapter;
    CCTPComposer public cctpComposer;
    AquaAdapter public aquaAdapter;
    LPAccount public accountImpl;
    Rebalancer public rebalancerImpl;
    address public accountAddr;
    bytes32 public wethStrategyHash;

    function run() external {
        // Detect chain and set per-chain addresses
        address lzEndpoint;
        address stargateEth;
        address usdc;

        if (block.chainid == BASE_CHAIN_ID) {
            lzEndpoint = LZ_ENDPOINT_BASE;
            stargateEth = STARGATE_ETH_BASE;
            usdc = USDC_BASE;
        } else if (block.chainid == UNICHAIN_CHAIN_ID) {
            lzEndpoint = LZ_ENDPOINT_UNICHAIN;
            stargateEth = STARGATE_ETH_UNICHAIN;
            usdc = USDC_UNICHAIN;
        } else {
            revert("DeployLocal: unsupported chain");
        }

        _deployContracts(lzEndpoint, stargateEth, usdc);
        _setupLPAccount(usdc);
        _setupSwapper(usdc);
        _writeJson(lzEndpoint, stargateEth, usdc);
    }

    function _deployContracts(address lzEndpoint, address stargateEth, address usdc) internal {
        vm.startBroadcast(DEPLOYER_KEY);

        // Deploy BridgeRegistry
        bridgeRegistry = new BridgeRegistry(DEPLOYER);

        accountImpl = new LPAccount(address(bridgeRegistry));

        // Deploy AccountFactory via CREATE3 (deterministic address across chains)
        bytes32 factorySalt = _buildFactorySalt(DEPLOYER);
        bytes memory factoryInitCode = abi.encodePacked(
            type(AccountFactory).creationCode, abi.encode(AQUA, SWAP_VM_ROUTER, CREATEX, address(accountImpl), DEPLOYER)
        );
        factory = AccountFactory(ICreateX(CREATEX).deployCreate3(factorySalt, factoryInitCode));

        rebalancerImpl = new Rebalancer();
        ERC1967Proxy rebalancerProxy =
            new ERC1967Proxy(address(rebalancerImpl), abi.encodeCall(Rebalancer.initialize, (DEPLOYER)));
        rebalancer = Rebalancer(address(rebalancerProxy));

        stargateAdapter = new StargateAdapter(DEPLOYER);
        stargateAdapter.registerPool(WETH, stargateEth);

        composer = new Composer(lzEndpoint, DEPLOYER);
        composer.registerPool(stargateEth, WETH);
        composer.setWeth(WETH);

        cctpAdapter = new CCTPAdapter(TOKEN_MESSENGER_V2, DEPLOYER);
        cctpComposer = new CCTPComposer(MESSAGE_TRANSMITTER_V2, usdc, DEPLOYER);

        aquaAdapter = new AquaAdapter(AQUA);

        // Configure BridgeRegistry
        bridgeRegistry.setAdapter(keccak256("STARGATE"), address(stargateAdapter));
        bridgeRegistry.setAdapter(keccak256("CCTP"), address(cctpAdapter));
        bridgeRegistry.addComposer(address(composer));
        bridgeRegistry.addComposer(address(cctpComposer));

        // Create account with signature-verified salt
        // Clear any EIP-7702 delegation code on the deployer (e.g., on Base mainnet fork)
        // so SignatureChecker.isValidSignatureNow treats it as an EOA for ECDSA recovery.
        vm.stopBroadcast();
        vm.etch(DEPLOYER, "");
        vm.startBroadcast(DEPLOYER_KEY);

        bytes32 messageHash = keccak256(abi.encodePacked("aqua0.create-account:", address(factory)));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DEPLOYER_KEY, ethSignedHash);
        accountAddr = factory.createAccount(abi.encodePacked(r, s, v));

        vm.stopBroadcast();
    }

    function _setupLPAccount(address usdc) internal {
        vm.startBroadcast(DEPLOYER_KEY);

        LPAccount lpAccount = LPAccount(payable(accountAddr));

        lpAccount.authorizeRebalancer(address(rebalancer));
        lpAccount.approveAqua(WETH, type(uint256).max);
        lpAccount.approveAqua(usdc, type(uint256).max);

        // Fund account with WETH
        IWETH(WETH).deposit{ value: ACCOUNT_WETH }();
        IWETH(WETH).transfer(accountAddr, ACCOUNT_WETH);

        // Ship a sample WETH strategy (LP flow: active strategy for swappers)
        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(accountAddr, 1);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory shipTokens = new address[](1);
        shipTokens[0] = WETH;
        uint256[] memory shipAmounts = new uint256[](1);
        shipAmounts[0] = STRATEGY_WETH;
        wethStrategyHash = lpAccount.ship(strategyBytes, shipTokens, shipAmounts);

        // Fund swapper with WETH
        IWETH(WETH).deposit{ value: SWAPPER_WETH }();
        IWETH(WETH).transfer(SWAPPER, SWAPPER_WETH);

        vm.stopBroadcast();
    }

    function _setupSwapper(address usdc) internal {
        vm.startBroadcast(SWAPPER_KEY);

        // Approve both Aqua and SwapVM Router for swap settlement
        IERC20Approve(WETH).approve(SWAP_VM_ROUTER, type(uint256).max);
        IERC20Approve(WETH).approve(AQUA, type(uint256).max);
        IERC20Approve(usdc).approve(SWAP_VM_ROUTER, type(uint256).max);
        IERC20Approve(usdc).approve(AQUA, type(uint256).max);

        vm.stopBroadcast();
    }

    function _writeJson(address lzEndpoint, address stargateEth, address usdc) internal {
        string memory obj = "deploy";
        vm.serializeAddress(obj, "aqua", AQUA);
        vm.serializeAddress(obj, "swapVMRouter", SWAP_VM_ROUTER);
        vm.serializeAddress(obj, "stargateEth", stargateEth);
        vm.serializeAddress(obj, "lzEndpoint", lzEndpoint);
        vm.serializeAddress(obj, "weth", WETH);
        vm.serializeAddress(obj, "usdc", usdc);
        vm.serializeAddress(obj, "deployer", DEPLOYER);
        vm.serializeAddress(obj, "swapper", SWAPPER);
        vm.serializeAddress(obj, "accountFactory", address(factory));
        vm.serializeAddress(obj, "rebalancer", address(rebalancer));
        vm.serializeAddress(obj, "stargateAdapter", address(stargateAdapter));
        vm.serializeAddress(obj, "composer", address(composer));
        vm.serializeAddress(obj, "bridgeRegistry", address(bridgeRegistry));
        vm.serializeAddress(obj, "tokenMessengerV2", TOKEN_MESSENGER_V2);
        vm.serializeAddress(obj, "messageTransmitterV2", MESSAGE_TRANSMITTER_V2);
        vm.serializeAddress(obj, "cctpAdapter", address(cctpAdapter));
        vm.serializeAddress(obj, "cctpComposer", address(cctpComposer));
        vm.serializeAddress(obj, "aquaAdapter", address(aquaAdapter));
        vm.serializeAddress(obj, "sampleAccount", accountAddr);
        vm.serializeAddress(obj, "accountImpl", address(accountImpl));
        vm.serializeAddress(obj, "rebalancerImpl", address(rebalancerImpl));
        vm.serializeAddress(obj, "beacon", address(factory.BEACON()));
        string memory json = vm.serializeBytes32(obj, "wethStrategyHash", wethStrategyHash);

        vm.writeJson(json, "./deployments/localhost.json");
    }
}
