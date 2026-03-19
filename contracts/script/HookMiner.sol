// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title HookMiner
/// @notice Off-chain helper to mine a CREATE2 salt such that the deployed hook address
///         has the required permission bits set in the lower 14 bits.
/// @dev Used in forge scripts — not deployed on-chain.
library HookMiner {
    /// @notice Find a CREATE2 salt so that `create2(deployer, salt, initCodeHash)`
    ///         produces an address whose lowest bits satisfy `flagMask`.
    /// @param deployer      The deployer address (CREATE2 factory or the script address)
    /// @param flagMask      The required bits in the hook address lower 14 bits
    ///                      e.g. BEFORE_SWAP (1<<7) | AFTER_SWAP (1<<6) = 0xC0
    /// @param initCodeHash  keccak256(creationCode) of the hook contract
    /// @param startSalt     Starting salt value (iterate from here)
    /// @return salt         The salt that produces a valid hook address
    /// @return hookAddress  The resulting CREATE2 hook address
    function find(
        address deployer,
        uint160 flagMask,
        bytes32 initCodeHash,
        uint256 startSalt
    ) internal pure returns (bytes32 salt, address hookAddress) {
        for (uint256 i = startSalt; i < startSalt + 200_000; i++) {
            salt = bytes32(i);
            hookAddress = _computeCreate2Address(deployer, salt, initCodeHash);
            // V4 validateHookPermissions checks the lower 14 bits exactly:
            // the address must have EXACTLY the declared permission bits set —
            // no extra undeclared bits allowed in bits [13:0].
            if ((uint160(hookAddress) & 0x3FFF) == flagMask) {
                return (salt, hookAddress);
            }
        }
        revert("HookMiner: no valid salt found in range");
    }

    function _computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address addr) {
        assembly {
            let ptr := mload(0x40)
            mstore8(ptr, 0xff)
            mstore(add(ptr, 0x01), shl(0x60, deployer))
            mstore(add(ptr, 0x15), salt)
            mstore(add(ptr, 0x35), initCodeHash)
            addr := keccak256(ptr, 0x55)
        }
    }
}
