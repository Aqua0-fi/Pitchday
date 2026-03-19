// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { ICreateX } from "../../src/interface/ICreateX.sol";

/// @title MockCreateX
/// @notice Implements CREATE3 behavior for unit testing without requiring the real CreateX (solc 0.8.23).
/// @dev CREATE3 works by: (1) CREATE2 deploys a minimal proxy, (2) proxy does CREATE at nonce=1.
///      The final address depends only on deployer + salt, not on the deployed contract bytecode.
///      This mock mirrors CreateX's _guard() salt processing for permissioned deploys.
contract MockCreateX is ICreateX {
    /// @notice Deploy using CREATE3 — address depends only on deployer (this) + guarded salt
    function deployCreate3(bytes32 salt, bytes memory initCode)
        external
        payable
        override
        returns (address newContract)
    {
        // Process salt via _guard (checks msg.sender against salt's permissioned address)
        bytes32 guardedSalt = _guard(salt);

        // Step 1: CREATE2 deploy the minimal proxy
        // Proxy creation code: 0x67363d3d37363d34f03d5260086018f3
        // This deploys runtime code: 363d3d37363d34f0
        //   CALLDATASIZE, RETURNDATASIZE(0), RETURNDATASIZE(0), CALLDATACOPY,
        //   CALLDATASIZE, RETURNDATASIZE(0), CALLVALUE, CREATE
        // The proxy copies calldata into memory and CREATEs a contract with it.
        bytes memory proxyCreationCode = hex"67363d3d37363d34f03d5260086018f3";
        address proxy;
        assembly {
            proxy := create2(0, add(proxyCreationCode, 0x20), mload(proxyCreationCode), guardedSalt)
        }
        require(proxy != address(0), "MockCreateX: proxy CREATE2 failed");

        // Step 2: Call proxy with initCode as calldata — proxy CREATEs the actual contract
        (bool success,) = proxy.call(initCode);
        require(success, "MockCreateX: proxy CREATE failed");

        // Step 3: Compute the deployed address (CREATE from proxy at nonce=1)
        // RLP([proxy, 1]) = 0xd6 0x94 <20-byte proxy> 0x01
        newContract =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), proxy, bytes1(0x01))))));

        // Verify the contract was actually deployed
        require(newContract.code.length > 0, "MockCreateX: deployment produced no code");
    }

    /// @notice Compute the CREATE3 address for a given salt and deployer
    /// @dev Mirrors CreateX's computeCreate3Address: guards the salt, computes CREATE2 proxy address,
    ///      then derives the final CREATE address from that proxy at nonce=1.
    function computeCreate3Address(bytes32 salt, address deployer) external view override returns (address) {
        bytes32 guardedSalt = keccak256(abi.encode(deployer, salt));
        bytes memory proxyCreationCode = hex"67363d3d37363d34f03d5260086018f3";
        address proxy = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), guardedSalt, keccak256(proxyCreationCode)))
                )
            )
        );
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), proxy, bytes1(0x01))))));
    }

    /// @dev Mirror CreateX's _guard() for salt processing.
    ///      When bytes 0-19 of salt == msg.sender: permissioned deploy.
    ///      Byte 20 == 0x00: no cross-chain protection (chainid excluded from hash).
    ///      Returns: keccak256(abi.encode(msg.sender, salt))
    function _guard(bytes32 salt) internal view returns (bytes32) {
        address saltAddress = address(bytes20(salt));

        if (saltAddress == msg.sender || saltAddress == address(0)) {
            return keccak256(abi.encode(msg.sender, salt));
        }
        revert("MockCreateX: unauthorized");
    }
}
