// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { Composer } from "../src/bridge/Composer.sol";
import { StargateAdapter } from "../src/bridge/StargateAdapter.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { Rebalancer } from "../src/rebalancer/Rebalancer.sol";
import { IAccount } from "../src/interface/IAccount.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { IERC20 } from "../src/interface/IERC20.sol";
import {
    IStargate,
    SendParam,
    MessagingFee as SgMessagingFee,
    MessagingReceipt as SgMessagingReceipt
} from "../src/interface/IStargate.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { Errors } from "../src/lib/Errors.sol";
import { RebalanceStatus } from "../src/lib/Types.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AccountTestHelper } from "./utils/AccountTestHelper.sol";

// ============================================
// MOCKS
// ============================================

contract MockAqua is IAqua {
    mapping(address => mapping(address => mapping(bytes32 => mapping(address => uint256)))) public virtualBalances;
    mapping(address => mapping(address => mapping(bytes32 => uint8))) public tokensCounts;

    function ship(address app, bytes memory strategy, address[] memory tokens, uint256[] memory amounts)
        external
        override
        returns (bytes32 strategyHash)
    {
        strategyHash = keccak256(strategy);
        address maker = msg.sender;
        uint8 tokensCount = uint8(tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            virtualBalances[maker][app][strategyHash][tokens[i]] += amounts[i];
            tokensCounts[maker][app][strategyHash] = tokensCount;
        }
    }

    function dock(address app, bytes32 strategyHash, address[] memory tokens) external override {
        address maker = msg.sender;
        for (uint256 i = 0; i < tokens.length; i++) {
            virtualBalances[maker][app][strategyHash][tokens[i]] = 0;
            tokensCounts[maker][app][strategyHash] = 0xff;
        }
    }

    function rawBalances(address maker, address app, bytes32 strategyHash, address token)
        external
        view
        override
        returns (uint248 balance, uint8 tokensCount)
    {
        balance = uint248(virtualBalances[maker][app][strategyHash][token]);
        tokensCount = tokensCounts[maker][app][strategyHash];
    }

    function safeBalances(address, address, bytes32, address, address)
        external
        pure
        override
        returns (uint256, uint256)
    {
        return (0, 0);
    }
}

contract MockERC20 is IERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

    contract MockStargate is IStargate {
        uint64 public nonceCounter;
        bytes32 public lastGuid;
        address public immutable tokenAddress;
        bool public shouldRevert;

        constructor(address _token) {
            tokenAddress = _token;
        }

        function setShouldRevert(bool _val) external {
            shouldRevert = _val;
        }

        function send(SendParam calldata _sendParam, SgMessagingFee calldata _fee, address)
            external
            payable
            override
            returns (SgMessagingReceipt memory receipt, uint256 amountOut)
        {
            if (shouldRevert) revert("stargate reverted");
            nonceCounter++;
            lastGuid = keccak256(abi.encode(_sendParam.dstEid, _sendParam.to, nonceCounter));
            receipt = SgMessagingReceipt({ guid: lastGuid, nonce: nonceCounter, fee: _fee });
            amountOut = _sendParam.amountLD;
        }

        function quoteSend(SendParam calldata, bool) external pure override returns (SgMessagingFee memory fee) {
            fee = SgMessagingFee({ nativeFee: 0.02 ether, lzTokenFee: 0 });
        }

        function token() external view override returns (address) {
            return tokenAddress;
        }
    }

    // Mock account that reverts on onCrosschainDeposit
    contract RevertingAquaAccount is IAccount {
        function onCrosschainDeposit(bytes memory, address[] memory, uint256[] memory)
            external
            pure
            override
            returns (bytes32)
        {
            revert("aqua ship failed");
        }

        function bridgeStargate(uint32, address, bytes calldata, address, uint256, uint256, uint128, uint128)
            external
            payable
            override
            returns (bytes32)
        {
            return bytes32(0);
        }

        function bridgeCCTP(uint32, address, bytes calldata, address, uint256, uint256, uint32)
            external
            payable
            override
            returns (uint64)
        {
            return 0;
        }
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    contract RebalancerIntegrationTest is Test {
        MockAqua public aqua;
        MockERC20 public token;
        MockStargate public stargate;
        LPAccount public srcAccount;
        LPAccount public dstAccount;
        Composer public composer;
        StargateAdapter public adapter;
        Rebalancer public rebalancer;
        BridgeRegistry public bridgeRegistry;

        LPAccount public accountImpl;
        UpgradeableBeacon public beacon;

        address public owner = address(this);
        address public factory = address(0xFACA);
        address public lzEndpoint = address(0xE1);
        address public swapVMRouter = address(0x5555);

        uint32 constant SRC_CHAIN = 8453;
        uint32 constant DST_CHAIN = 130;
        uint32 constant ARB_EID = 30110;
        uint256 constant AMOUNT = 1000 ether;

        bytes public strategyBytes = "integration-strategy";
        bytes32 public strategyHash;

        address[] public tokens;
        uint256[] public amounts;

        receive() external payable { }

        function setUp() public {
            aqua = new MockAqua();
            token = new MockERC20();
            stargate = new MockStargate(address(token));

            // Deploy BridgeRegistry
            bridgeRegistry = new BridgeRegistry(owner);

            accountImpl = new LPAccount(address(bridgeRegistry));
            beacon = new UpgradeableBeacon(address(accountImpl), address(this));
            srcAccount =
                AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);
            dstAccount =
                AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);
            composer = new Composer(lzEndpoint, owner);
            composer.registerPool(address(stargate), address(token));
            adapter = new StargateAdapter(owner);
            adapter.registerPool(address(token), address(stargate));
            Rebalancer rebalancerImpl = new Rebalancer();
            ERC1967Proxy rebalancerProxy =
                new ERC1967Proxy(address(rebalancerImpl), abi.encodeCall(Rebalancer.initialize, (owner)));
            rebalancer = Rebalancer(address(rebalancerProxy));

            strategyHash = keccak256(strategyBytes);

            tokens = new address[](1);
            tokens[0] = address(token);
            amounts = new uint256[](1);
            amounts[0] = AMOUNT;

            // Register composer as trusted in BridgeRegistry
            bridgeRegistry.addComposer(address(composer));

            // Authorize rebalancer on source
            srcAccount.authorizeRebalancer(address(rebalancer));
        }

        // ============================================
        // FULL FLOW TESTS
        // ============================================

        function test_full_rebalance_flow_with_compose() public {
            // Ship on source
            srcAccount.ship(strategyBytes, tokens, amounts);

            // Trigger rebalance
            bytes32 opId = rebalancer.triggerRebalance(
                address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT
            );

            // Dock on source
            rebalancer.executeDock(opId, strategyHash);
            (,,,,,, RebalanceStatus statusDocked,,) = rebalancer.operations(opId);
            assertEq(uint256(statusDocked), uint256(RebalanceStatus.DOCKED));

            // Bridge (mock)
            bytes32 guid = keccak256("bridge-guid");
            rebalancer.recordBridging(opId, guid);

            // Simulate compose on destination
            token.mint(address(composer), AMOUNT);
            bytes memory appMsg = abi.encode(address(dstAccount), strategyBytes, tokens, amounts);
            bytes memory oftMsg = OFTComposeMsgCodec.encode(
                uint64(1), 30184, AMOUNT, abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg)
            );

            vm.prank(lzEndpoint);
            composer.lzCompose(address(stargate), guid, oftMsg, address(0), "");

            // Confirm
            rebalancer.confirmRebalance(opId);
            (,,,,,, RebalanceStatus statusFinal,, uint256 completedAt) = rebalancer.operations(opId);
            assertEq(uint256(statusFinal), uint256(RebalanceStatus.COMPLETED));
            assertGt(completedAt, 0);

            // Verify destination Aqua balance
            (uint248 balance,) = aqua.rawBalances(address(dstAccount), swapVMRouter, strategyHash, address(token));
            assertEq(balance, AMOUNT);
        }

        function test_rebalance_failure_at_dock_stage() public {
            // Ship a strategy
            srcAccount.ship(strategyBytes, tokens, amounts);

            // Trigger rebalance
            bytes32 opId = rebalancer.triggerRebalance(
                address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT
            );

            // Try to dock with wrong strategy hash
            bytes32 wrongHash = keccak256("wrong-strategy");
            vm.expectRevert(Errors.StrategyTokensNotFound.selector);
            rebalancer.executeDock(opId, wrongHash);

            // Fail the rebalance
            rebalancer.failRebalance(opId, "dock failed: wrong strategy");
            (,,,,,, RebalanceStatus status,,) = rebalancer.operations(opId);
            assertEq(uint256(status), uint256(RebalanceStatus.FAILED));
        }

        function test_rebalance_failure_at_bridge_stage() public {
            srcAccount.ship(strategyBytes, tokens, amounts);
            bytes32 opId = rebalancer.triggerRebalance(
                address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT
            );
            rebalancer.executeDock(opId, strategyHash);

            // Stargate reverts
            stargate.setShouldRevert(true);

            // Fail the rebalance
            rebalancer.failRebalance(opId, "bridge failed: stargate error");
            (,,,,,, RebalanceStatus status,,) = rebalancer.operations(opId);
            assertEq(uint256(status), uint256(RebalanceStatus.FAILED));
        }

        function test_rebalance_compose_failure_at_destination() public {
            srcAccount.ship(strategyBytes, tokens, amounts);
            bytes32 opId = rebalancer.triggerRebalance(
                address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT
            );
            rebalancer.executeDock(opId, strategyHash);
            rebalancer.recordBridging(opId, keccak256("guid"));

            // Set up composer pointing to a reverting account
            RevertingAquaAccount revertAccount = new RevertingAquaAccount();
            token.mint(address(composer), AMOUNT);

            bytes memory appMsg = abi.encode(address(revertAccount), strategyBytes, tokens, amounts);
            bytes memory oftMsg = OFTComposeMsgCodec.encode(
                uint64(1), 30184, AMOUNT, abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg)
            );

            vm.prank(lzEndpoint);
            vm.expectRevert("aqua ship failed");
            composer.lzCompose(address(stargate), keccak256("guid"), oftMsg, address(0), "");
        }

        function test_two_concurrent_rebalances_for_same_account() public {
            // Ship two strategies
            bytes memory strategy1 = "strategy-1";
            bytes memory strategy2 = "strategy-2";
            srcAccount.ship(strategy1, tokens, amounts);
            srcAccount.ship(strategy2, tokens, amounts);

            // Trigger two rebalances
            bytes32 opId1 =
                rebalancer.triggerRebalance(address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT);
            vm.warp(block.timestamp + 1); // ensure unique opId
            bytes32 opId2 =
                rebalancer.triggerRebalance(address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT);

            assertTrue(opId1 != opId2);

            // Process first
            rebalancer.executeDock(opId1, keccak256(strategy1));
            rebalancer.recordBridging(opId1, keccak256("guid-1"));
            rebalancer.confirmRebalance(opId1);

            // Process second
            rebalancer.executeDock(opId2, keccak256(strategy2));
            rebalancer.recordBridging(opId2, keccak256("guid-2"));
            rebalancer.confirmRebalance(opId2);

            (,,,,,, RebalanceStatus s1,,) = rebalancer.operations(opId1);
            (,,,,,, RebalanceStatus s2,,) = rebalancer.operations(opId2);
            assertEq(uint256(s1), uint256(RebalanceStatus.COMPLETED));
            assertEq(uint256(s2), uint256(RebalanceStatus.COMPLETED));
        }

        function test_concurrent_rebalance_different_accounts() public {
            LPAccount account2 =
                AccountTestHelper.deployAccountProxy(address(beacon), owner, factory, address(aqua), swapVMRouter);
            account2.authorizeRebalancer(address(rebalancer));
            account2.ship(strategyBytes, tokens, amounts);
            srcAccount.ship(strategyBytes, tokens, amounts);

            bytes32 opId1 =
                rebalancer.triggerRebalance(address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT);
            bytes32 opId2 = rebalancer.triggerRebalance(address(account2), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT);

            rebalancer.executeDock(opId1, strategyHash);
            rebalancer.executeDock(opId2, strategyHash);
            rebalancer.recordBridging(opId1, keccak256("g1"));
            rebalancer.recordBridging(opId2, keccak256("g2"));
            rebalancer.confirmRebalance(opId1);
            rebalancer.confirmRebalance(opId2);

            (,,,,,, RebalanceStatus s1,,) = rebalancer.operations(opId1);
            (,,,,,, RebalanceStatus s2,,) = rebalancer.operations(opId2);
            assertEq(uint256(s1), uint256(RebalanceStatus.COMPLETED));
            assertEq(uint256(s2), uint256(RebalanceStatus.COMPLETED));
        }

        function test_ship_new_strategy_after_dock() public {
            // Ship and dock strategy A
            srcAccount.ship(strategyBytes, tokens, amounts);
            srcAccount.dock(strategyHash);

            // Ship strategy B
            bytes memory strategyB = "strategy-B";
            bytes32 hashB = srcAccount.ship(strategyB, tokens, amounts);

            (uint248 balance,) = aqua.rawBalances(address(srcAccount), swapVMRouter, hashB, address(token));
            assertEq(balance, AMOUNT);
        }

        function test_compose_with_aqua_ship_failure() public {
            RevertingAquaAccount revertAccount = new RevertingAquaAccount();
            token.mint(address(composer), AMOUNT);

            bytes memory appMsg = abi.encode(address(revertAccount), strategyBytes, tokens, amounts);
            bytes memory oftMsg = OFTComposeMsgCodec.encode(
                uint64(1), 30184, AMOUNT, abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg)
            );

            vm.prank(lzEndpoint);
            vm.expectRevert("aqua ship failed");
            composer.lzCompose(address(stargate), keccak256("guid"), oftMsg, address(0), "");

            // Tokens should remain in composer (transfer happened before revert)
            // Actually the entire tx reverts, so tokens stay in composer
            assertEq(token.balanceOf(address(revertAccount)), 0);
        }

        function test_compose_insufficient_balance() public {
            // Composer has 0 tokens, but OFT message says amountLD = 1000 ether
            Composer emptyComposer = new Composer(lzEndpoint, owner);
            emptyComposer.registerPool(address(stargate), address(token));
            bridgeRegistry.addComposer(address(emptyComposer));

            bytes memory appMsg = abi.encode(address(dstAccount), strategyBytes, tokens, amounts);
            bytes memory oftMsg = OFTComposeMsgCodec.encode(
                uint64(1), 30184, AMOUNT, abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg)
            );

            vm.prank(lzEndpoint);
            vm.expectRevert(); // SafeERC20 will revert
            emptyComposer.lzCompose(address(stargate), keccak256("guid"), oftMsg, address(0), "");
        }

        function test_compose_zero_amount_in_oft() public {
            token.mint(address(composer), AMOUNT);

            bytes memory appMsg = abi.encode(address(dstAccount), strategyBytes, tokens, amounts);
            bytes memory oftMsg = OFTComposeMsgCodec.encode(
                uint64(1), 30184, 0, abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg)
            );

            vm.prank(lzEndpoint);
            vm.expectRevert(Errors.ZeroAmount.selector);
            composer.lzCompose(address(stargate), keccak256("guid"), oftMsg, address(0), "");
        }

        function test_dock_twice_succeeds_in_mock() public {
            srcAccount.ship(strategyBytes, tokens, amounts);
            srcAccount.dock(strategyHash);

            // Account doesn't clear _strategyTokens on dock, so second dock re-sends the same
            // tokens array to MockAqua. In production Aqua would reject this, but mock allows it.
            srcAccount.dock(strategyHash);

            (uint248 balance, uint8 tokensCount) =
                aqua.rawBalances(address(srcAccount), swapVMRouter, strategyHash, address(token));
            assertEq(balance, 0);
            assertEq(tokensCount, 0xff);
        }

        function test_reauthorize_after_revoke() public {
            srcAccount.ship(strategyBytes, tokens, amounts);

            // Revoke
            srcAccount.revokeRebalancer();
            assertFalse(srcAccount.rebalancerAuthorized());

            // Re-authorize
            srcAccount.authorizeRebalancer(address(rebalancer));
            assertTrue(srcAccount.rebalancerAuthorized());
            assertEq(srcAccount.rebalancer(), address(rebalancer));

            // Rebalancer works again
            bytes32 opId = rebalancer.triggerRebalance(
                address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), AMOUNT
            );
            rebalancer.executeDock(opId, strategyHash);
            (,,,,,, RebalanceStatus status,,) = rebalancer.operations(opId);
            assertEq(uint256(status), uint256(RebalanceStatus.DOCKED));
        }

        // ============================================
        // DOCK-RESHIP-BRIDGE PATTERN
        // ============================================

        function test_dock_full_amount_reship_remainder_bridge_portion() public {
            // Ship 1000 on source
            srcAccount.ship(strategyBytes, tokens, amounts);

            // Trigger rebalance for 300 (partial)
            uint256 bridgeAmount = 300 ether;
            uint256 remainderAmount = AMOUNT - bridgeAmount; // 700
            bytes32 opId =
                rebalancer.triggerRebalance(address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), bridgeAmount);

            // Step 1: Dock the full amount on source
            rebalancer.executeDock(opId, strategyHash);
            (,,,,,, RebalanceStatus statusDocked,,) = rebalancer.operations(opId);
            assertEq(uint256(statusDocked), uint256(RebalanceStatus.DOCKED));

            // Verify Aqua balance is zeroed on source (tokensCount = 0xff means docked)
            (uint248 srcBalanceAfterDock, uint8 tokensCountAfterDock) =
                aqua.rawBalances(address(srcAccount), swapVMRouter, strategyHash, address(token));
            assertEq(srcBalanceAfterDock, 0);
            assertEq(tokensCountAfterDock, 0xff);

            // Step 2: Reship the remainder (700) on source with same strategy
            uint256[] memory remainderAmounts = new uint256[](1);
            remainderAmounts[0] = remainderAmount;
            srcAccount.ship(strategyBytes, tokens, remainderAmounts);

            // Verify source has 700 virtual balance
            (uint248 srcBalanceAfterReship,) =
                aqua.rawBalances(address(srcAccount), swapVMRouter, strategyHash, address(token));
            assertEq(srcBalanceAfterReship, remainderAmount);

            // Step 3: Bridge the 300 portion to destination via compose
            bytes32 guid = keccak256("bridge-guid");
            rebalancer.recordBridging(opId, guid);

            // Simulate compose on destination - bridge delivers 300 tokens
            token.mint(address(composer), bridgeAmount);
            uint256[] memory bridgeAmounts = new uint256[](1);
            bridgeAmounts[0] = bridgeAmount;
            bytes memory appMsg = abi.encode(address(dstAccount), strategyBytes, tokens, bridgeAmounts);
            bytes memory oftMsg = OFTComposeMsgCodec.encode(
                uint64(1), 30184, bridgeAmount, abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg)
            );

            vm.prank(lzEndpoint);
            composer.lzCompose(address(stargate), guid, oftMsg, address(0), "");

            // Confirm rebalance
            rebalancer.confirmRebalance(opId);
            (,,,,,, RebalanceStatus statusFinal,,) = rebalancer.operations(opId);
            assertEq(uint256(statusFinal), uint256(RebalanceStatus.COMPLETED));

            // Verify final state: source has 700, destination has 300
            (uint248 srcFinal,) = aqua.rawBalances(address(srcAccount), swapVMRouter, strategyHash, address(token));
            (uint248 dstFinal,) = aqua.rawBalances(address(dstAccount), swapVMRouter, strategyHash, address(token));
            assertEq(srcFinal, remainderAmount, "source should have 700");
            assertEq(dstFinal, bridgeAmount, "destination should have 300");
        }

        function test_rebalance_after_reship_on_source() public {
            // === First rebalance: dock-reship-bridge ===
            srcAccount.ship(strategyBytes, tokens, amounts);

            uint256 firstBridgeAmount = 300 ether;
            uint256 firstRemainder = AMOUNT - firstBridgeAmount;

            bytes32 opId1 =
                rebalancer.triggerRebalance(
                address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), firstBridgeAmount
            );
            rebalancer.executeDock(opId1, strategyHash);

            // Reship remainder on source
            uint256[] memory remainderAmounts = new uint256[](1);
            remainderAmounts[0] = firstRemainder;
            srcAccount.ship(strategyBytes, tokens, remainderAmounts);

            // Bridge portion to destination
            bytes32 guid1 = keccak256("guid-1");
            rebalancer.recordBridging(opId1, guid1);

            token.mint(address(composer), firstBridgeAmount);
            uint256[] memory bridgeAmounts1 = new uint256[](1);
            bridgeAmounts1[0] = firstBridgeAmount;
            bytes memory appMsg1 = abi.encode(address(dstAccount), strategyBytes, tokens, bridgeAmounts1);
            bytes memory oftMsg1 = OFTComposeMsgCodec.encode(
                uint64(1),
                30184,
                firstBridgeAmount,
                abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg1)
            );

            vm.prank(lzEndpoint);
            composer.lzCompose(address(stargate), guid1, oftMsg1, address(0), "");
            rebalancer.confirmRebalance(opId1);

            // === Second rebalance from the reshipped strategy ===
            uint256 secondBridgeAmount = 200 ether;

            vm.warp(block.timestamp + 1);
            bytes32 opId2 = rebalancer.triggerRebalance(
                address(srcAccount), SRC_CHAIN, DST_CHAIN, address(token), secondBridgeAmount
            );
            rebalancer.executeDock(opId2, strategyHash);

            // Reship remainder again
            uint256[] memory remainderAmounts2 = new uint256[](1);
            remainderAmounts2[0] = firstRemainder - secondBridgeAmount; // 500
            srcAccount.ship(strategyBytes, tokens, remainderAmounts2);

            // Bridge second portion
            bytes32 guid2 = keccak256("guid-2");
            rebalancer.recordBridging(opId2, guid2);

            token.mint(address(composer), secondBridgeAmount);
            uint256[] memory bridgeAmounts2 = new uint256[](1);
            bridgeAmounts2[0] = secondBridgeAmount;
            bytes memory appMsg2 = abi.encode(address(dstAccount), strategyBytes, tokens, bridgeAmounts2);
            bytes memory oftMsg2 = OFTComposeMsgCodec.encode(
                uint64(2),
                30184,
                secondBridgeAmount,
                abi.encodePacked(bytes32(uint256(uint160(address(stargate)))), appMsg2)
            );

            vm.prank(lzEndpoint);
            composer.lzCompose(address(stargate), guid2, oftMsg2, address(0), "");
            rebalancer.confirmRebalance(opId2);

            // Verify: source has 500, destination has 300 + 200 = 500
            (uint248 srcFinal,) = aqua.rawBalances(address(srcAccount), swapVMRouter, strategyHash, address(token));
            (uint248 dstFinal,) = aqua.rawBalances(address(dstAccount), swapVMRouter, strategyHash, address(token));
            assertEq(srcFinal, 500 ether, "source should have 500");
            assertEq(dstFinal, 500 ether, "destination should have 500");

            // Both operations completed
            (,,,,,, RebalanceStatus s1,,) = rebalancer.operations(opId1);
            (,,,,,, RebalanceStatus s2,,) = rebalancer.operations(opId2);
            assertEq(uint256(s1), uint256(RebalanceStatus.COMPLETED));
            assertEq(uint256(s2), uint256(RebalanceStatus.COMPLETED));
        }
    }
