// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "forge-std/Script.sol";

/// @title DeployBase
/// @author Aqua0 Team
/// @notice Shared constants and helpers for Aqua0 deployment scripts.
/// @dev The factory salt version is read from FACTORY_VERSION env var (default: "v1").
abstract contract DeployBase is Script {
    // ── Shared addresses (same on Base + Unichain) ──────────────────────────
    address constant AQUA = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;
    address constant SWAP_VM_ROUTER = 0x8fDD04Dbf6111437B44bbca99C28882434e0958f;
    address constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address constant MESSAGE_TRANSMITTER_V2 = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    // ── Base-specific ───────────────────────────────────────────────────────
    address constant LZ_ENDPOINT_BASE = 0x1a44076050125825900e736c501f859c50fE728c;
    address constant STARGATE_ETH_BASE = 0xdc181Bd607330aeeBEF6ea62e03e5e1Fb4B6F7C7;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // ── Unichain-specific ───────────────────────────────────────────────────
    address constant LZ_ENDPOINT_UNICHAIN = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address constant STARGATE_ETH_UNICHAIN = 0xe9aBA835f813ca05E50A6C0ce65D0D74390F7dE7;
    address constant USDC_UNICHAIN = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;

    // ── Chain IDs ───────────────────────────────────────────────────────────
    uint256 constant BASE_CHAIN_ID = 8453;
    uint256 constant UNICHAIN_CHAIN_ID = 130;

    /// @dev Build a CreateX-compatible salt for deploying AccountFactory via CREATE3.
    ///      Salt format (32 bytes):
    ///        Bytes 0-19:  deployer address (permissioned deploy)
    ///        Byte 20:     0x00 (no cross-chain redeploy protection — block.chainid excluded)
    ///        Bytes 21-31: bytes11(keccak256("aqua0.account-factory.<version>"))
    ///      Version is read from FACTORY_VERSION env var (default: "v1").
    function _buildFactorySalt(address deployer) internal returns (bytes32) {
        string memory version = vm.envOr("FACTORY_VERSION", string("v1"));
        console.log("Factory salt version:", version);
        return bytes32(
            abi.encodePacked(
                deployer, bytes1(0x00), bytes11(keccak256(bytes(string.concat("aqua0.account-factory.", version))))
            )
        );
    }
}
