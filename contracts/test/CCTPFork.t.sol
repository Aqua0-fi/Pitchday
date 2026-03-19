// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test, Vm } from "forge-std/Test.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { CCTPAdapter } from "../src/bridge/CCTPAdapter.sol";
import { CCTPComposer } from "../src/bridge/CCTPComposer.sol";
import { BridgeRegistry } from "../src/bridge/BridgeRegistry.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";
import { AccountTestHelper } from "./utils/AccountTestHelper.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Fork tests that hit real Circle CCTP v2 contracts on Base/Unichain.
/// @dev Requires BASE_RPC_URL (and UNICHAIN_RPC_URL for Unichain tests). Skips when not set.
///      Run with: BASE_RPC_URL=... UNICHAIN_RPC_URL=... forge test --match-path test/CCTPFork.t.sol -vvv
///
///      NOTE: The deployed TokenMessengerV2 proxy does not return a nonce from depositForBurnWithHook
///      (the implementation ends with STOP opcode). CCTPAdapter handles this gracefully via low-level
///      call, returning nonce=0 when no return data is available. Fork tests verify the burn succeeded
///      via balance checks and Circle's MessageSent event instead of relying on the nonce value.
contract CCTPForkTest is Test {
    /// @dev Circle's TokenMessengerV2 (same on Base + Unichain)
    address constant TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    /// @dev Circle's MessageTransmitterV2 (same on Base + Unichain)
    address constant MESSAGE_TRANSMITTER_V2 = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    /// @dev USDC on Base
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    /// @dev USDC on Unichain
    address constant USDC_UNICHAIN = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;

    /// @dev CCTP domain IDs
    uint32 constant DOMAIN_BASE = 6;
    uint32 constant DOMAIN_UNICHAIN = 10;

    /// @dev Aqua (1inch) — same on Base + Unichain
    address constant AQUA = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;
    /// @dev SwapVM Router — same on Base + Unichain
    address constant SWAP_VM = 0x8fDD04Dbf6111437B44bbca99C28882434e0958f;

    /// @dev Circle's MessageSent event topic (emitted by MessageTransmitterV2)
    bytes32 constant MESSAGE_SENT_TOPIC = keccak256("MessageSent(bytes)");

    /// @dev Accept ETH (not needed for CCTP but keeps test contract flexible)
    receive() external payable { }

    // ── Helpers ─────────────────────────────────────────────────────────────

    /// @notice Deploy CCTPAdapter pointing at real TokenMessengerV2
    function _deployCCTPAdapter() internal returns (CCTPAdapter) {
        return new CCTPAdapter(TOKEN_MESSENGER_V2, address(this));
    }

    /// @notice Deploy an Account with BridgeRegistry + CCTPAdapter registered
    function _deployAccountWithCCTP(address _owner, address usdc)
        internal
        returns (LPAccount account, BridgeRegistry registry, CCTPAdapter adapter)
    {
        registry = new BridgeRegistry(address(this));
        adapter = _deployCCTPAdapter();

        // Register CCTP adapter
        registry.setAdapter(keccak256("CCTP"), address(adapter));

        // Deploy CCTPComposer and add as trusted composer
        CCTPComposer cctpComposer = new CCTPComposer(MESSAGE_TRANSMITTER_V2, usdc, address(this));
        registry.addComposer(address(cctpComposer));

        // Deploy Account with BridgeRegistry
        LPAccount impl = new LPAccount(address(registry));
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        account = AccountTestHelper.deployAccountProxy(address(beacon), _owner, address(0xFACA), AQUA, SWAP_VM);
    }

    /// @notice Check if Circle's MessageSent event was emitted in recorded logs
    function _hasMessageSentEvent(Vm.Log[] memory logs) internal pure returns (bool) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == MESSAGE_SENT_TOPIC) {
                return true;
            }
        }
        return false;
    }

    /// @notice Check if CCTPBridged event was emitted in recorded logs
    function _hasCCTPBridgedEvent(Vm.Log[] memory logs) internal pure returns (bool) {
        bytes32 topic = keccak256("CCTPBridged(uint32,address,address,uint256,uint64)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return true;
            }
        }
        return false;
    }

    // =============================================
    // Base fork tests
    // =============================================

    /// @notice CCTPAdapter calls real TokenMessengerV2 with real USDC; verifies USDC burned and events emitted
    function testFork_base_cctpAdapter_bridgeWithHook_burns_usdc() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        CCTPAdapter adapter = _deployCCTPAdapter();
        uint256 amount = 100e6; // 100 USDC
        address recipient = address(0xBEEF);
        bytes memory hookData = abi.encode(recipient, bytes("test-strategy"), new address[](0), new uint256[](0));

        // Fund this contract with real USDC via deal
        deal(USDC_BASE, address(this), amount);
        assertEq(IERC20Minimal(USDC_BASE).balanceOf(address(this)), amount, "should have USDC");

        // Approve adapter to pull USDC
        IERC20Minimal(USDC_BASE).approve(address(adapter), amount);

        // Record logs to capture events
        vm.recordLogs();

        // Bridge via real TokenMessengerV2
        adapter.bridgeWithHook(
            USDC_BASE,
            amount,
            DOMAIN_UNICHAIN, // destination domain
            recipient,
            hookData,
            0, // maxFee
            1000 // minFinalityThreshold
        );

        // Verify USDC was burned (balance should be 0)
        assertEq(IERC20Minimal(USDC_BASE).balanceOf(address(this)), 0, "USDC should be burned from caller");
        assertEq(IERC20Minimal(USDC_BASE).balanceOf(address(adapter)), 0, "adapter should have no USDC");

        // Verify events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(_hasCCTPBridgedEvent(logs), "CCTPBridged event should be emitted");
        assertTrue(_hasMessageSentEvent(logs), "Circle MessageSent event should be emitted");
    }

    /// @notice Account.bridgeCCTP() -> BridgeRegistry -> CCTPAdapter -> real TokenMessengerV2
    function testFork_base_account_bridgeCCTP_via_registry() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        (LPAccount account,,) = _deployAccountWithCCTP(address(this), USDC_BASE);
        uint256 amount = 50e6; // 50 USDC
        address dstComposer = address(0xCAFE);
        bytes memory hookData = abi.encode(address(account), bytes("test"), new address[](0), new uint256[](0));

        // Fund account with real USDC
        deal(USDC_BASE, address(account), amount);
        assertEq(IERC20Minimal(USDC_BASE).balanceOf(address(account)), amount, "account should have USDC");

        // Call bridgeCCTP as owner
        account.bridgeCCTP(
            DOMAIN_UNICHAIN,
            dstComposer,
            hookData,
            USDC_BASE,
            amount,
            0, // maxFee
            1000 // minFinalityThreshold
        );

        // Verify USDC burned from account
        assertEq(IERC20Minimal(USDC_BASE).balanceOf(address(account)), 0, "USDC should be burned from account");
    }

    /// @notice Validation still works on fork — zero amount reverts
    function testFork_base_cctpAdapter_reverts_zero_amount() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        CCTPAdapter adapter = _deployCCTPAdapter();

        vm.expectRevert(Errors.ZeroAmount.selector);
        adapter.bridgeWithHook(USDC_BASE, 0, DOMAIN_UNICHAIN, address(0xBEEF), "", 0, 1000);
    }

    /// @notice Verify CCTPComposer can be deployed pointing at real MessageTransmitterV2 and USDC
    function testFork_base_cctpComposer_deployed_with_real_addresses() public {
        string memory baseUrl = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(baseUrl).length == 0) return;

        vm.createSelectFork(baseUrl);

        CCTPComposer cctpComposer = new CCTPComposer(MESSAGE_TRANSMITTER_V2, USDC_BASE, address(this));

        assertEq(cctpComposer.MESSAGE_TRANSMITTER(), MESSAGE_TRANSMITTER_V2, "transmitter should match");
        assertEq(cctpComposer.TOKEN(), USDC_BASE, "token should match");
        assertEq(cctpComposer.owner(), address(this), "owner should match");
    }

    // =============================================
    // Unichain fork tests
    // =============================================

    /// @notice Same outbound test on Unichain fork with Unichain USDC
    function testFork_unichain_cctpAdapter_bridgeWithHook_burns_usdc() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);

        CCTPAdapter adapter = _deployCCTPAdapter();
        uint256 amount = 100e6; // 100 USDC
        address recipient = address(0xBEEF);
        bytes memory hookData = abi.encode(recipient, bytes("test-strategy"), new address[](0), new uint256[](0));

        // Fund with Unichain USDC
        deal(USDC_UNICHAIN, address(this), amount);
        assertEq(IERC20Minimal(USDC_UNICHAIN).balanceOf(address(this)), amount, "should have USDC");

        // Approve and bridge
        IERC20Minimal(USDC_UNICHAIN).approve(address(adapter), amount);

        vm.recordLogs();

        adapter.bridgeWithHook(
            USDC_UNICHAIN,
            amount,
            DOMAIN_BASE, // destination: Base
            recipient,
            hookData,
            0,
            1000
        );

        // Verify USDC was burned
        assertEq(IERC20Minimal(USDC_UNICHAIN).balanceOf(address(this)), 0, "USDC should be burned");
        assertEq(IERC20Minimal(USDC_UNICHAIN).balanceOf(address(adapter)), 0, "adapter should have no USDC");

        // Verify events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(_hasCCTPBridgedEvent(logs), "CCTPBridged event should be emitted");
        assertTrue(_hasMessageSentEvent(logs), "Circle MessageSent event should be emitted");
    }

    /// @notice Full Account.bridgeCCTP flow on Unichain
    function testFork_unichain_account_bridgeCCTP_via_registry() public {
        string memory unichainUrl = vm.envOr("UNICHAIN_RPC_URL", string(""));
        if (bytes(unichainUrl).length == 0) return;

        vm.createSelectFork(unichainUrl);

        (LPAccount account,,) = _deployAccountWithCCTP(address(this), USDC_UNICHAIN);
        uint256 amount = 50e6; // 50 USDC
        address dstComposer = address(0xCAFE);
        bytes memory hookData = abi.encode(address(account), bytes("test"), new address[](0), new uint256[](0));

        // Fund account with Unichain USDC
        deal(USDC_UNICHAIN, address(account), amount);
        assertEq(IERC20Minimal(USDC_UNICHAIN).balanceOf(address(account)), amount, "account should have USDC");

        account.bridgeCCTP(
            DOMAIN_BASE, // destination: Base
            dstComposer,
            hookData,
            USDC_UNICHAIN,
            amount,
            0,
            1000
        );

        // Verify USDC burned from account
        assertEq(IERC20Minimal(USDC_UNICHAIN).balanceOf(address(account)), 0, "USDC should be burned from account");
    }
}
