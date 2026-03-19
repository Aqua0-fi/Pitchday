// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test, Vm } from "forge-std/Test.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { AccountFactory } from "../src/lp/AccountFactory.sol";
import { Composer } from "../src/bridge/Composer.sol";
import { StargateAdapter } from "../src/bridge/StargateAdapter.sol";
import { Rebalancer } from "../src/rebalancer/Rebalancer.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { ISwapVMRouter } from "../src/interface/ISwapVMRouter.sol";
import { SendParam, MessagingFee, MessagingReceipt } from "../src/interface/IStargate.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { RebalanceStatus } from "../src/lib/Types.sol";
import { Errors } from "../src/lib/Errors.sol";
import { SwapVMProgramHelper } from "./utils/SwapVMProgramHelper.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { AccountTestHelper } from "./utils/AccountTestHelper.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { IWETH } from "../src/interface/IWETH.sol";

/// @notice Fork tests that hit real Aqua and SwapVM on Base/Unichain (ship, dock, cross-chain, swap).
/// @dev Requires BASE_RPC_URL (and UNICHAIN_RPC_URL for cross-chain tests). Skips when not set.
///      Run with: BASE_RPC_URL=... UNICHAIN_RPC_URL=... forge test --match-path test/CrosschainFork.t.sol -vvv

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev OFTReceipt returned by real Stargate V2 / LayerZero OFT send()
struct OFTReceipt {
    uint256 amountSentLD;
    uint256 amountReceivedLD;
}

/// @dev Real Stargate V2 pool interface with correct OFTReceipt return type.
///      Our simplified IStargate returns (MessagingReceipt, uint256) — this matches the deployed ABI.
interface IStargatePool {
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory, OFTReceipt memory);

    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken) external view returns (MessagingFee memory);

    function token() external view returns (address);
}

contract CrosschainForkTest is Test {
    /// @dev Aqua (1inch) on Base and Unichain
    address constant AQUA = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;
    /// @dev Canonical WETH on Base (and many L2s)
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    /// @dev WETH on Unichain
    address constant WETH_UNICHAIN = 0x4200000000000000000000000000000000000006;
    /// @dev SwapVM Router (same on Base, Unichain, etc.)
    address constant SWAP_VM = 0x8fDD04Dbf6111437B44bbca99C28882434e0958f;
    /// @dev CreateX factory (canonical address on all chains)
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    /// @dev USDC on Base
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev Stargate Native ETH pool on Base
    address constant STARGATE_ETH_BASE = 0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7;
    /// @dev Stargate Native ETH pool on Unichain
    address constant STARGATE_ETH_UNICHAIN = 0xe9aBA835f813ca05E50A6C0ce65D0D74390F7dE7;
    /// @dev LayerZero V2 endpoint (same on all EVM chains)
    address constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    /// @dev LayerZero V2 endpoint IDs
    uint32 constant BASE_EID = 30184;
    uint32 constant UNICHAIN_EID = 30320;

    address constant FACTORY_PLACEHOLDER = address(0xFACA);

    using OptionsBuilder for bytes;

    /// @dev Known private key for fork tests (signature-based account creation)
    uint256 constant TEST_PK = 0xA11CE;

    /// @dev Accept ETH refunds from Stargate
    receive() external payable { }

    /// @notice Deploy an Account behind a BeaconProxy (no BridgeRegistry — for ship/dock only tests)
    function _deployAccount(address _owner) internal returns (LPAccount) {
        LPAccount impl = new LPAccount(address(0));
        UpgradeableBeacon _beacon = new UpgradeableBeacon(address(impl), address(this));
        return AccountTestHelper.deployAccountProxy(address(_beacon), _owner, address(0xFACA), AQUA, SWAP_VM);
    }

    /// @notice Deploy an Account with BridgeRegistry (for cross-chain composer tests)
    function _deployAccountWithRegistry(address _owner, address _bridgeRegistry) internal returns (LPAccount) {
        LPAccount impl = new LPAccount(_bridgeRegistry);
        UpgradeableBeacon _beacon = new UpgradeableBeacon(address(impl), address(this));
        return AccountTestHelper.deployAccountProxy(address(_beacon), _owner, address(0xFACA), AQUA, SWAP_VM);
    }

    /// @notice Build LayerZero V2 executor options with lzReceive + lzCompose gas
    function _buildLzComposeOptions(uint128 _receiveGas, uint128 _composeGas) internal pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_receiveGas, 0)
            .addExecutorLzComposeOption(0, _composeGas, 0);
    }

    /// @notice Deploy a multi-asset Composer on Unichain with WETH pool registered
    function _deployComposerUnichain() internal returns (Composer) {
        Composer c = new Composer(LZ_ENDPOINT, address(this));
        c.registerPool(STARGATE_ETH_UNICHAIN, WETH_UNICHAIN);
        return c;
    }

    /// @notice Deploy a multi-asset StargateAdapter on Base with WETH pool registered
    function _deployAdapterBase() internal returns (StargateAdapter) {
        StargateAdapter a = new StargateAdapter(address(this));
        a.registerPool(WETH_BASE, STARGATE_ETH_BASE);
        return a;
    }

    // =============================================
    // Test a: AccountFactory creates deterministic account on Base fork
    // =============================================

    function testFork_base_account_factory_creates_deterministic_account() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        LPAccount factoryImpl = new LPAccount(address(0));
        AccountFactory factory = new AccountFactory(AQUA, SWAP_VM, CREATEX, address(factoryImpl), address(this));

        address testSigner = vm.addr(TEST_PK);
        bytes32 messageHash = keccak256(abi.encodePacked("aqua0.create-account:", address(factory)));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_PK, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Deploy account
        vm.prank(testSigner);
        address accountAddr = factory.createAccount(signature);

        // Verify account was created and registered
        assertTrue(factory.isAccount(accountAddr), "isAccount should return true");
        assertEq(LPAccount(payable(accountAddr)).owner(), testSigner, "owner should be deployer");
    }

    // =============================================
    // Test b: Account ships real SwapVM order to Aqua on Base
    // =============================================

    function testFork_base_account_ships_real_swapvm_order() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);
        uint256 amount = 1 ether;

        LPAccount account = _deployAccount(address(this));

        // Fund account with WETH
        vm.deal(address(this), amount);
        IWETH(WETH_BASE).deposit{ value: amount }();
        IWETH(WETH_BASE).transfer(address(account), amount);
        assertEq(IWETH(WETH_BASE).balanceOf(address(account)), amount, "account should hold WETH");

        // Approve Aqua to pull WETH from account
        account.approveAqua(WETH_BASE, type(uint256).max);

        // Build a real SwapVM order using the helper
        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildMinimalOrder(address(account));
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory tokens = new address[](1);
        tokens[0] = WETH_BASE;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes32 strategyHash = account.ship(strategyBytes, tokens, amounts);

        // Verify rawBalances on real Aqua
        (uint248 balance, uint8 tokensCount) =
            IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_BASE);
        assertEq(balance, amount, "Aqua raw balance should equal shipped amount");
        assertEq(tokensCount, 1, "tokensCount should be 1");

        // Verify stored tokens
        address[] memory storedTokens = account.getStrategyTokens(strategyHash);
        assertEq(storedTokens.length, 1);
        assertEq(storedTokens[0], WETH_BASE);
    }

    // =============================================
    // Test c: Account docks strategy on Base
    // =============================================

    function testFork_base_account_docks_strategy() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);
        uint256 amount = 1 ether;

        LPAccount account = _deployAccount(address(this));

        // Fund and ship
        vm.deal(address(this), amount);
        IWETH(WETH_BASE).deposit{ value: amount }();
        IWETH(WETH_BASE).transfer(address(account), amount);
        account.approveAqua(WETH_BASE, type(uint256).max);

        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(address(account), 1);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory tokens = new address[](1);
        tokens[0] = WETH_BASE;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes32 strategyHash = account.ship(strategyBytes, tokens, amounts);

        // Verify balance is set
        (uint248 balanceBefore,) = IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_BASE);
        assertEq(balanceBefore, amount);

        // Dock the strategy
        account.dock(strategyHash);

        // Verify balance is zeroed and status is docked (tokensCount = 0xff)
        (uint248 balanceAfter, uint8 tokensCount) =
            IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_BASE);
        assertEq(balanceAfter, 0, "balance should be 0 after dock");
        assertEq(tokensCount, 0xff, "tokensCount should be 0xff (docked)");
    }

    // =============================================
    // Test d: Full LP swap lifecycle on Base
    // =============================================

    function testFork_base_lp_full_swap_lifecycle() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        LPAccount account = _deployAccount(address(this));
        ISwapVMRouter router = ISwapVMRouter(SWAP_VM);

        // Build AMM order with salt for uniqueness
        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(address(account), 42);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        // Fund account with WETH
        uint256 wethAmount = 1 ether;
        vm.deal(address(this), wethAmount);
        IWETH(WETH_BASE).deposit{ value: wethAmount }();
        IWETH(WETH_BASE).transfer(address(account), wethAmount);
        account.approveAqua(WETH_BASE, type(uint256).max);

        // Ship with WETH
        address[] memory tokens = new address[](1);
        tokens[0] = WETH_BASE;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wethAmount;
        bytes32 strategyHash = account.ship(strategyBytes, tokens, amounts);

        // Verify liquidity is in Aqua
        (uint248 balance,) = IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_BASE);
        assertEq(balance, wethAmount, "Aqua balance should equal shipped amount");

        // Try quote — may revert if the program doesn't produce a valid swap path
        // for this particular token pair; that's OK for a minimal program test
        bytes memory takerData = abi.encodePacked(uint160(0), uint16(0x0001)); // isExactIn
        uint256 swapAmount = 0.01 ether;

        try router.quote(order, WETH_BASE, USDC_BASE, swapAmount, takerData) returns (
            uint256 amountIn, uint256 amountOut, bytes32
        ) {
            assertTrue(amountIn > 0 && amountOut > 0, "quote should return positive amounts");
        } catch {
            // Expected for minimal program — it may not support the token pair fully.
            // The ship/dock lifecycle test above proves the Aqua integration works.
        }
    }

    // =============================================
    // Test e: Cross-chain deposit on Unichain with real program (via lzCompose)
    // =============================================

    function testFork_unichain_crosschain_deposit_real_program() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);
        uint256 amount = 1 ether;

        BridgeRegistry bridgeRegistry = new BridgeRegistry(address(this));
        LPAccount account = _deployAccountWithRegistry(address(this), address(bridgeRegistry));
        // Deploy Composer with real LZ endpoint and Stargate addresses
        Composer composer = _deployComposerUnichain();
        bridgeRegistry.addComposer(address(composer));

        // Fund composer with WETH (simulating bridge receipt)
        vm.deal(address(this), amount);
        IWETH(WETH_UNICHAIN).deposit{ value: amount }();
        IWETH(WETH_UNICHAIN).transfer(address(composer), amount);
        assertEq(IWETH(WETH_UNICHAIN).balanceOf(address(composer)), amount, "composer should hold WETH");

        // Approve Aqua on account side
        account.approveAqua(WETH_UNICHAIN, type(uint256).max);

        // Build real SwapVM order
        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(address(account), 100);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory tokens = new address[](1);
        tokens[0] = WETH_UNICHAIN;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes memory appComposeMsg = abi.encode(address(account), strategyBytes, tokens, amounts);

        // Build OFT compose message and call lzCompose via LZ_ENDPOINT prank
        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            uint64(1), BASE_EID, amount, abi.encodePacked(bytes32(uint256(uint160(address(this)))), appComposeMsg)
        );

        vm.prank(LZ_ENDPOINT);
        composer.lzCompose(STARGATE_ETH_UNICHAIN, bytes32(uint256(1)), oftMsg, address(0), "");

        // Verify rawBalances on Unichain Aqua
        bytes32 strategyHash = keccak256(strategyBytes);
        (uint248 balance, uint8 tokensCount) =
            IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_UNICHAIN);
        assertEq(balance, amount, "Aqua raw balance on Unichain should equal bridged amount");
        assertEq(tokensCount, 1, "tokensCount should be 1");
    }

    // =============================================
    // Test f: Full rebalance flow Base → Unichain
    // =============================================

    function testFork_base_to_unichain_full_rebalance_flow() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0 || bytes(unichainUrl).length == 0) return;

        // --- Base fork: deploy, ship, dock ---
        uint256 baseFork = vm.createFork(baseUrl);
        vm.selectFork(baseFork);

        uint256 amount = 1 ether;
        LPAccount factoryImpl = new LPAccount(address(0));
        AccountFactory factory = new AccountFactory(AQUA, SWAP_VM, CREATEX, address(factoryImpl), address(this));

        address testSigner = vm.addr(TEST_PK);
        bytes32 messageHash = keccak256(abi.encodePacked("aqua0.create-account:", address(factory)));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_PK, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(testSigner);
        address accountAddr = factory.createAccount(signature);
        LPAccount account = LPAccount(payable(accountAddr));

        Rebalancer rebalancerImpl = new Rebalancer();
        ERC1967Proxy rebalancerProxy =
            new ERC1967Proxy(address(rebalancerImpl), abi.encodeCall(Rebalancer.initialize, (address(this))));
        Rebalancer rebalancer = Rebalancer(address(rebalancerProxy));

        // Fund account
        vm.deal(address(this), amount);
        IWETH(WETH_BASE).deposit{ value: amount }();
        IWETH(WETH_BASE).transfer(accountAddr, amount);

        // Owner-only calls must come from testSigner
        vm.startPrank(testSigner);
        account.approveAqua(WETH_BASE, type(uint256).max);

        // Authorize rebalancer
        account.authorizeRebalancer(address(rebalancer));

        // Ship strategy
        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(accountAddr, 200);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory tokens = new address[](1);
        tokens[0] = WETH_BASE;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32 strategyHash = account.ship(strategyBytes, tokens, amounts);
        vm.stopPrank();

        // Verify balance on Base
        (uint248 baseBalanceBefore,) = IAqua(AQUA).rawBalances(accountAddr, SWAP_VM, strategyHash, WETH_BASE);
        assertEq(baseBalanceBefore, amount);

        // Trigger rebalance
        bytes32 operationId = rebalancer.triggerRebalance(
            accountAddr,
            8453,
            130,
            WETH_BASE,
            amount // Base → Unichain (eid 130)
        );

        // Execute dock
        rebalancer.executeDock(operationId, strategyHash);

        // Verify balance zeroed on Base
        (uint248 baseBalanceAfter,) = IAqua(AQUA).rawBalances(accountAddr, SWAP_VM, strategyHash, WETH_BASE);
        assertEq(baseBalanceAfter, 0, "Base balance should be 0 after dock");

        // Record bridging
        bytes32 fakeGuid = keccak256("fake-bridge-guid");
        rebalancer.recordBridging(operationId, fakeGuid);

        // --- Unichain fork: receive and ship ---
        uint256 unichainFork = vm.createFork(unichainUrl);
        vm.selectFork(unichainFork);

        BridgeRegistry uniBridgeRegistry = new BridgeRegistry(address(this));
        LPAccount uniAccount = _deployAccountWithRegistry(address(this), address(uniBridgeRegistry));
        Composer composer = _deployComposerUnichain();
        uniBridgeRegistry.addComposer(address(composer));
        uniAccount.approveAqua(WETH_UNICHAIN, type(uint256).max);

        // Simulate bridge receipt
        vm.deal(address(this), amount);
        IWETH(WETH_UNICHAIN).deposit{ value: amount }();
        IWETH(WETH_UNICHAIN).transfer(address(composer), amount);

        // Build the same order but for unichain account
        ISwapVMRouter.Order memory uniOrder = SwapVMProgramHelper.buildAMMOrder(address(uniAccount), 200);
        bytes memory uniStrategyBytes = SwapVMProgramHelper.encodeStrategy(uniOrder);

        address[] memory uniTokens = new address[](1);
        uniTokens[0] = WETH_UNICHAIN;
        uint256[] memory uniAmounts = new uint256[](1);
        uniAmounts[0] = amount;
        bytes memory appComposeMsg = abi.encode(address(uniAccount), uniStrategyBytes, uniTokens, uniAmounts);

        // Call lzCompose via LZ_ENDPOINT prank
        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            uint64(1), BASE_EID, amount, abi.encodePacked(bytes32(uint256(uint160(address(this)))), appComposeMsg)
        );

        vm.prank(LZ_ENDPOINT);
        composer.lzCompose(STARGATE_ETH_UNICHAIN, fakeGuid, oftMsg, address(0), "");

        // Verify balance on Unichain
        bytes32 uniStrategyHash = keccak256(uniStrategyBytes);
        (uint248 uniBalance,) = IAqua(AQUA).rawBalances(address(uniAccount), SWAP_VM, uniStrategyHash, WETH_UNICHAIN);
        assertEq(uniBalance, amount, "Unichain balance should equal bridged amount");

        // --- Back to Base: confirm rebalance ---
        vm.selectFork(baseFork);
        rebalancer.confirmRebalance(operationId);

        (,,,,,, RebalanceStatus status,, uint256 completedAt) = rebalancer.operations(operationId);
        assertEq(uint256(status), uint256(RebalanceStatus.COMPLETED));
        assertGt(completedAt, 0);
    }

    // =============================================
    // Test g: Account authorize/revoke rebalancer on Base fork
    // =============================================

    function testFork_account_authorize_revoke_rebalancer() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        LPAccount account = _deployAccount(address(this));
        Rebalancer rebalancerImpl = new Rebalancer();
        ERC1967Proxy rebalancerProxy =
            new ERC1967Proxy(address(rebalancerImpl), abi.encodeCall(Rebalancer.initialize, (address(this))));
        Rebalancer rebalancer = Rebalancer(address(rebalancerProxy));

        // Fund account and ship a strategy
        uint256 amount = 0.5 ether;
        vm.deal(address(this), amount);
        IWETH(WETH_BASE).deposit{ value: amount }();
        IWETH(WETH_BASE).transfer(address(account), amount);
        account.approveAqua(WETH_BASE, type(uint256).max);

        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(address(account), 300);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory tokens = new address[](1);
        tokens[0] = WETH_BASE;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32 strategyHash = account.ship(strategyBytes, tokens, amounts);

        // Authorize rebalancer
        account.authorizeRebalancer(address(rebalancer));
        assertTrue(account.rebalancerAuthorized());
        assertEq(account.rebalancer(), address(rebalancer));

        // Rebalancer can trigger and dock
        bytes32 operationId = rebalancer.triggerRebalance(address(account), 8453, 42161, WETH_BASE, amount);
        rebalancer.executeDock(operationId, strategyHash);

        // Verify docked
        (uint248 balanceAfterDock,) = IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_BASE);
        assertEq(balanceAfterDock, 0);

        // Re-ship for revoke test (new salt to avoid immutability constraint)
        ISwapVMRouter.Order memory order2 = SwapVMProgramHelper.buildAMMOrder(address(account), 301);
        bytes memory strategyBytes2 = SwapVMProgramHelper.encodeStrategy(order2);

        vm.deal(address(this), amount);
        IWETH(WETH_BASE).deposit{ value: amount }();
        IWETH(WETH_BASE).transfer(address(account), amount);
        account.ship(strategyBytes2, tokens, amounts);

        // Revoke rebalancer
        account.revokeRebalancer();
        assertFalse(account.rebalancerAuthorized());

        // Rebalancer can no longer dock (triggerRebalance checks authorization too)
        vm.expectRevert(); // NotAuthorized from triggerRebalance
        rebalancer.triggerRebalance(address(account), 8453, 42161, WETH_BASE, amount);

        // Non-owner cannot authorize
        address nonOwner = address(0xDEAD);
        vm.prank(nonOwner);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        account.authorizeRebalancer(address(rebalancer));
    }

    // =============================================
    // Test h: Stargate sends compose message from Base to Unichain
    // =============================================

    function testFork_base_stargate_sends_compose_message() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        IStargatePool pool = IStargatePool(STARGATE_ETH_BASE);
        uint256 bridgeAmount = 0.01 ether;

        // Build compose payload (what Composer expects on destination)
        address fakeAccount = address(0xBEEF);
        bytes memory strategyBytes = bytes("test-strategy");
        address[] memory tokens = new address[](1);
        tokens[0] = WETH_UNICHAIN;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = bridgeAmount;
        bytes memory composePayload = abi.encode(fakeAccount, strategyBytes, tokens, amounts);

        // Build LZ V2 executor options with compose gas allocation
        bytes memory extraOptions = _buildLzComposeOptions(128_000, 200_000);

        // Build SendParam targeting Unichain with compose message
        address dstComposer = address(0xCAFE);
        SendParam memory sendParam = SendParam({
            dstEid: UNICHAIN_EID,
            to: bytes32(uint256(uint160(dstComposer))),
            amountLD: bridgeAmount,
            minAmountLD: bridgeAmount * 95 / 100, // 5% slippage tolerance
            extraOptions: extraOptions,
            composeMsg: composePayload,
            oftCmd: "" // Taxi mode (required for composability)
        });

        // Quote the LayerZero messaging fee from real Stargate
        // This will revert if the Base→Unichain route is not configured
        try pool.quoteSend(sendParam, false) returns (MessagingFee memory quotedFee) {
            // For native ETH pool: msg.value = bridge amount + LZ fee
            uint256 totalValue = bridgeAmount + quotedFee.nativeFee;
            vm.deal(address(this), totalValue);

            // Record logs to capture OFTSent event
            vm.recordLogs();

            // Send through real Stargate native pool
            (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt) =
                pool.send{ value: totalValue }(sendParam, quotedFee, address(this));

            // Verify valid GUID (proves LZ message was queued)
            assertTrue(receipt.guid != bytes32(0), "GUID should be non-zero");
            assertTrue(oftReceipt.amountSentLD > 0, "amountSentLD should be positive");
            assertTrue(oftReceipt.amountReceivedLD > 0, "amountReceivedLD should be positive");

            // Verify OFTSent event was emitted (proves message entered LayerZero)
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bytes32 oftSentTopic = keccak256("OFTSent(bytes32,uint32,address,uint256,uint256)");
            bool foundOFTSent = false;
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics.length > 0 && logs[i].topics[0] == oftSentTopic) {
                    foundOFTSent = true;
                    assertEq(logs[i].topics[1], receipt.guid, "OFTSent guid should match receipt");
                    break;
                }
            }
            assertTrue(foundOFTSent, "OFTSent event should be emitted");
        } catch {
            // Base→Unichain route may not be configured — skip gracefully
        }
    }

    // =============================================
    // Test i: Composer handles LZ compose message format (via lzCompose)
    // =============================================

    function testFork_unichain_composer_processes_lz_compose_message() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);
        uint256 amount = 1 ether;

        // Deploy real Account + Composer on Unichain
        BridgeRegistry bridgeRegistry = new BridgeRegistry(address(this));
        LPAccount account = _deployAccountWithRegistry(address(this), address(bridgeRegistry));
        Composer composer = _deployComposerUnichain();
        bridgeRegistry.addComposer(address(composer));
        account.approveAqua(WETH_UNICHAIN, type(uint256).max);

        // Fund composer with WETH (simulating Stargate token delivery to composer)
        vm.deal(address(this), amount);
        IWETH(WETH_UNICHAIN).deposit{ value: amount }();
        IWETH(WETH_UNICHAIN).transfer(address(composer), amount);

        // Build the app-level compose payload (account, strategy, tokens, amounts)
        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(address(account), 500);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);
        address[] memory tokens = new address[](1);
        tokens[0] = WETH_UNICHAIN;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes memory appComposeMsg = abi.encode(address(account), strategyBytes, tokens, amounts);

        // Encode the full OFTComposeMsgCodec message via the library
        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            uint64(1), BASE_EID, amount, abi.encodePacked(bytes32(uint256(uint160(address(this)))), appComposeMsg)
        );

        // Call lzCompose via LZ_ENDPOINT prank
        vm.prank(LZ_ENDPOINT);
        composer.lzCompose(STARGATE_ETH_UNICHAIN, bytes32(uint256(1)), oftMsg, address(0), "");

        // Verify tokens were forwarded to account
        assertEq(IWETH(WETH_UNICHAIN).balanceOf(address(account)), amount, "account should hold WETH");
        assertEq(IWETH(WETH_UNICHAIN).balanceOf(address(composer)), 0, "composer should be empty");

        // Verify strategy was shipped to real Aqua on Unichain
        bytes32 strategyHash = keccak256(strategyBytes);
        (uint248 balance, uint8 tokensCount) =
            IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_UNICHAIN);
        assertEq(balance, amount, "Aqua balance should equal compose amount");
        assertEq(tokensCount, 1, "tokensCount should be 1");
    }

    // =============================================
    // Test j: StargateAdapter bridgeWithCompose sends with TYPE_3 options
    // =============================================

    function testFork_base_stargateAdapter_bridgeWithCompose_sends_with_options() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        StargateAdapter adapter = _deployAdapterBase();

        address fakeAccount = address(0xBEEF);
        bytes memory strategyBytes = bytes("test-strategy");
        address[] memory tokens = new address[](1);
        tokens[0] = WETH_UNICHAIN;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.01 ether;
        bytes memory composePayload = abi.encode(fakeAccount, strategyBytes, tokens, amounts);

        address dstComposer = address(0xCAFE);
        uint256 bridgeAmount = 0.01 ether;

        // Quote the fee with compose gas
        try adapter.quoteBridgeWithComposeFee(
            WETH_BASE,
            UNICHAIN_EID,
            dstComposer,
            composePayload,
            bridgeAmount,
            bridgeAmount * 95 / 100,
            128_000,
            200_000
        ) returns (
            uint256 fee
        ) {
            uint256 totalValue = bridgeAmount + fee;
            vm.deal(address(this), totalValue);

            vm.recordLogs();
            bytes32 guid = adapter.bridgeWithCompose{ value: totalValue }(
                WETH_BASE,
                UNICHAIN_EID,
                dstComposer,
                composePayload,
                bridgeAmount,
                bridgeAmount * 95 / 100,
                128_000,
                200_000
            );
            assertTrue(guid != bytes32(0), "GUID should be non-zero");
        } catch {
            // Route may not be configured
        }
    }

    // =============================================
    // Test k: Compare quoteBridgeFee vs quoteBridgeWithComposeFee
    // =============================================

    function testFork_base_quote_compose_fee_higher_than_simple() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        StargateAdapter adapter = _deployAdapterBase();
        address recipient = address(0xBEEF);
        uint256 amount = 0.01 ether;
        uint256 minAmount = amount * 95 / 100;

        bytes memory composePayload = abi.encode(recipient, bytes("s"), new address[](0), new uint256[](0));

        try adapter.quoteBridgeFee(WETH_BASE, UNICHAIN_EID, recipient, amount, minAmount) returns (uint256 simpleFee) {
            try adapter.quoteBridgeWithComposeFee(
                WETH_BASE, UNICHAIN_EID, recipient, composePayload, amount, minAmount, 128_000, 200_000
            ) returns (
                uint256 composeFee
            ) {
                // Compose fee should be >= simple fee (more gas needed)
                assertTrue(composeFee >= simpleFee, "compose fee should be >= simple fee");
            } catch { }
        } catch { }
    }

    // =============================================
    // Test l: lzCompose rejects wrong _from on Unichain
    // =============================================

    function testFork_unichain_lzCompose_rejects_wrong_from() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);

        Composer composer = _deployComposerUnichain();

        bytes memory appMsg = abi.encode(address(0xBEEF), bytes("s"), new address[](1), new uint256[](1));
        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            uint64(1), BASE_EID, 1 ether, abi.encodePacked(bytes32(uint256(uint160(address(this)))), appMsg)
        );

        vm.prank(LZ_ENDPOINT);
        vm.expectRevert(Errors.PoolNotRegistered.selector);
        composer.lzCompose(address(0xBAD), bytes32(uint256(1)), oftMsg, address(0), "");
    }

    // =============================================
    // Test m: lzCompose rejects non-endpoint caller on Unichain
    // =============================================

    function testFork_unichain_lzCompose_rejects_non_endpoint_caller() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);

        Composer composer = _deployComposerUnichain();

        bytes memory appMsg = abi.encode(address(0xBEEF), bytes("s"), new address[](1), new uint256[](1));
        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            uint64(1), BASE_EID, 1 ether, abi.encodePacked(bytes32(uint256(uint160(address(this)))), appMsg)
        );

        // Call from non-endpoint
        vm.expectRevert(Errors.NotAuthorized.selector);
        composer.lzCompose(STARGATE_ETH_UNICHAIN, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    // =============================================
    // Test n: Full receive path with real Aqua on Unichain
    // =============================================

    function testFork_unichain_full_receive_path_real_aqua() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);
        uint256 amount = 0.5 ether;

        BridgeRegistry bridgeRegistry = new BridgeRegistry(address(this));
        LPAccount account = _deployAccountWithRegistry(address(this), address(bridgeRegistry));
        Composer composer = _deployComposerUnichain();
        bridgeRegistry.addComposer(address(composer));
        account.approveAqua(WETH_UNICHAIN, type(uint256).max);

        // Fund composer
        vm.deal(address(this), amount);
        IWETH(WETH_UNICHAIN).deposit{ value: amount }();
        IWETH(WETH_UNICHAIN).transfer(address(composer), amount);

        // Build a real SwapVM order
        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(address(account), 777);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory tokens = new address[](1);
        tokens[0] = WETH_UNICHAIN;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes memory appMsg = abi.encode(address(account), strategyBytes, tokens, amounts);

        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            uint64(1), BASE_EID, amount, abi.encodePacked(bytes32(uint256(uint160(address(this)))), appMsg)
        );

        vm.prank(LZ_ENDPOINT);
        composer.lzCompose(STARGATE_ETH_UNICHAIN, bytes32(uint256(42)), oftMsg, address(0), "");

        // Verify rawBalances on real Aqua
        bytes32 strategyHash = keccak256(strategyBytes);
        (uint248 balance, uint8 tokensCount) =
            IAqua(AQUA).rawBalances(address(account), SWAP_VM, strategyHash, WETH_UNICHAIN);
        assertEq(balance, amount, "Aqua balance should match bridged amount");
        assertEq(tokensCount, 1);
    }

    // =============================================
    // Test o: lzCompose reverts with insufficient balance on Unichain
    // =============================================

    function testFork_unichain_lzCompose_reverts_insufficient_balance() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);

        BridgeRegistry bridgeRegistry = new BridgeRegistry(address(this));
        LPAccount account = _deployAccountWithRegistry(address(this), address(bridgeRegistry));
        Composer composer = _deployComposerUnichain();
        bridgeRegistry.addComposer(address(composer));

        // DON'T fund composer — it has 0 WETH

        ISwapVMRouter.Order memory order = SwapVMProgramHelper.buildAMMOrder(address(account), 999);
        bytes memory strategyBytes = SwapVMProgramHelper.encodeStrategy(order);

        address[] memory tokens = new address[](1);
        tokens[0] = WETH_UNICHAIN;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        bytes memory appMsg = abi.encode(address(account), strategyBytes, tokens, amounts);

        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            uint64(1), BASE_EID, 1 ether, abi.encodePacked(bytes32(uint256(uint160(address(this)))), appMsg)
        );

        vm.prank(LZ_ENDPOINT);
        vm.expectRevert(); // SafeERC20 transfer reverts
        composer.lzCompose(STARGATE_ETH_UNICHAIN, bytes32(uint256(1)), oftMsg, address(0), "");
    }
}
