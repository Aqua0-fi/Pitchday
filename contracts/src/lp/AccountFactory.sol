// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Account } from "./Account.sol";
import { ICreateX } from "../interface/ICreateX.sol";
import { Errors } from "../lib/Errors.sol";
import { Events } from "../lib/Events.sol";

/// @title AccountFactory
/// @author Aqua0 Team
/// @notice Factory for creating LP accounts behind BeaconProxy
/// @dev Uses CreateX CREATE3 for deterministic addresses across chains.
///      CREATE3 addresses depend only on deployer + salt (not bytecode or constructor args),
///      so the same owner + salt produces the same account address on any chain regardless of
///      AQUA or SWAP_VM_ROUTER addresses.
///      All Account proxies share the same implementation via UpgradeableBeacon.
///      Salt is derived from a signed message for non-gameable determinism.
contract AccountFactory is Ownable {
    /// @notice Aqua protocol address
    address public immutable AQUA;

    /// @notice SwapVM Router address (passed to new accounts)
    address public immutable SWAP_VM_ROUTER;

    /// @notice CreateX factory for CREATE3 deployments
    ICreateX public immutable CREATEX;

    /// @notice UpgradeableBeacon that all Account proxies point to
    UpgradeableBeacon public immutable BEACON;

    /// @notice Mapping of owner => salt => account address
    mapping(address => mapping(bytes32 => address)) public accounts;

    /// @notice Mapping to check if account exists
    mapping(address => bool) public isAccount;

    /// @notice Constructor
    /// @param _aqua The Aqua protocol address
    /// @param _swapVMRouter The SwapVM Router address
    /// @param _createX The CreateX factory address
    /// @param _accountImpl The Account implementation address
    /// @param _owner The factory owner address
    constructor(address _aqua, address _swapVMRouter, address _createX, address _accountImpl, address _owner)
        Ownable(_owner)
    {
        if (_aqua == address(0)) revert Errors.ZeroAddress();
        if (_swapVMRouter == address(0)) revert Errors.ZeroAddress();
        if (_createX == address(0)) revert Errors.ZeroAddress();
        if (_accountImpl == address(0)) revert Errors.ZeroAddress();

        AQUA = _aqua;
        SWAP_VM_ROUTER = _swapVMRouter;
        CREATEX = ICreateX(_createX);
        BEACON = new UpgradeableBeacon(_accountImpl, address(this));
    }

    /// @notice Create a new LP account with signature-verified salt
    /// @dev Salt = keccak256(signature) where signature is over a chain-agnostic create-account message.
    ///      Supports EOA (ECDSA) + ERC-1271 (smart accounts) via SignatureChecker.
    ///      Message is chain-agnostic: keccak256("aqua0.create-account:", factoryAddress)
    ///      Same signature → same salt → same CREATE3 address on every chain.
    /// @param signature The signature over the create-account message
    /// @return account The created account address
    function createAccount(bytes calldata signature) external returns (address account) {
        address owner = msg.sender;

        // Derive salt from signature (non-gameable: only the signer can produce this)
        bytes32 salt = keccak256(signature);

        // Verify signature: msg.sender signed a create-account message
        // Chain-agnostic: no block.chainid — same message on every chain
        bytes32 messageHash = keccak256(abi.encodePacked("aqua0.create-account:", address(this)));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (!SignatureChecker.isValidSignatureNow(owner, ethSignedHash, signature)) {
            revert Errors.InvalidSignature();
        }

        if (accounts[owner][salt] != address(0)) {
            revert Errors.AccountAlreadyExists();
        }

        bytes32 createXSalt = _buildSalt(owner, salt);
        // Deploy BeaconProxy instead of Account directly
        bytes memory initData = abi.encodeCall(Account.initialize, (owner, address(this), AQUA, SWAP_VM_ROUTER));
        bytes memory initCode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(BEACON), initData));
        account = CREATEX.deployCreate3(createXSalt, initCode);

        if (account == address(0)) revert Errors.AccountNotFound();

        accounts[owner][salt] = account;
        isAccount[account] = true;

        emit Events.AccountCreated(account, owner, salt);
    }

    /// @notice Get account address for owner and salt
    /// @param owner The account owner address
    /// @param salt The salt used during account creation
    /// @return The account address, or address(0) if not created
    function getAccount(address owner, bytes32 salt) external view returns (address) {
        return accounts[owner][salt];
    }

    /// @notice Upgrade the Account implementation for all proxies
    /// @dev Only callable by the factory owner. Atomically upgrades ALL Account proxies.
    /// @param newImpl The new Account implementation address
    function upgradeAccountImplementation(address newImpl) external onlyOwner {
        if (newImpl == address(0)) revert Errors.ZeroAddress();
        BEACON.upgradeTo(newImpl);
        emit Events.AccountImplementationUpgraded(newImpl);
    }

    /// @notice Build a CreateX-compatible salt for CREATE3
    /// @dev Salt format (32 bytes):
    ///      - Bytes 0-19:  address(this) — permissioned deploy (only this factory can deploy)
    ///      - Byte 20:     0x00 — no cross-chain redeploy protection (block.chainid excluded)
    ///      - Bytes 21-31: bytes11(keccak256(owner, salt)) — entropy encoding LP identity
    ///      This ensures: same factory address + same owner + same salt → same account address on any chain
    function _buildSalt(address owner, bytes32 salt) internal view returns (bytes32) {
        return bytes32(abi.encodePacked(address(this), bytes1(0x00), bytes11(keccak256(abi.encodePacked(owner, salt)))));
    }
}
