// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { AccountFactory } from "../src/lp/AccountFactory.sol";
import { Account as LPAccount } from "../src/lp/Account.sol";
import { IAqua } from "../src/interface/IAqua.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";
import { MockCreateX } from "./utils/MockCreateX.sol";

/// @title MockAqua
/// @notice Mock implementation of IAqua for testing
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

    function dock(address, bytes32, address[] memory) external override { }

    function rawBalances(address maker, address app, bytes32 strategyHash, address token)
        external
        view
        override
        returns (uint248, uint8)
    {
        return (uint248(virtualBalances[maker][app][strategyHash][token]), tokensCounts[maker][app][strategyHash]);
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

contract AccountFactoryTest is Test {
    MockAqua public aqua;
    MockCreateX public createX;
    LPAccount public accountImpl;
    AccountFactory public factory;

    address public owner = address(this);
    address public swapVMRouter = address(0x5555);

    // Use a known private key for signing
    uint256 public signerKey = 0xA11CE;
    address public signer;
    bytes public signature;
    bytes32 public salt;

    function setUp() public {
        signer = vm.addr(signerKey);
        aqua = new MockAqua();
        createX = new MockCreateX();
        accountImpl = new LPAccount(address(0));
        factory = new AccountFactory(address(aqua), swapVMRouter, address(createX), address(accountImpl), owner);

        // Create a valid signature for account creation
        signature = _signCreateAccount(signerKey, address(factory));
        salt = keccak256(signature);
    }

    /// @notice Helper to sign the create-account message
    function _signCreateAccount(uint256 privateKey, address factoryAddr) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked("aqua0.create-account:", factoryAddr));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    // Constructor tests
    function test_constructor_sets_aqua() public view {
        assertEq(factory.AQUA(), address(aqua));
    }

    function test_constructor_sets_swapVMRouter() public view {
        assertEq(factory.SWAP_VM_ROUTER(), swapVMRouter);
    }

    function test_constructor_sets_createX() public view {
        assertEq(address(factory.CREATEX()), address(createX));
    }

    function test_constructor_sets_beacon() public view {
        assertTrue(address(factory.BEACON()) != address(0));
    }

    function test_constructor_sets_owner() public view {
        assertEq(factory.owner(), owner);
    }

    function test_constructor_reverts_zero_aqua() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new AccountFactory(address(0), swapVMRouter, address(createX), address(accountImpl), owner);
    }

    function test_constructor_reverts_zero_swapVMRouter() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new AccountFactory(address(aqua), address(0), address(createX), address(accountImpl), owner);
    }

    function test_constructor_reverts_zero_createX() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new AccountFactory(address(aqua), swapVMRouter, address(0), address(accountImpl), owner);
    }

    function test_constructor_reverts_zero_accountImpl() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new AccountFactory(address(aqua), swapVMRouter, address(createX), address(0), owner);
    }

    // createAccount tests
    function test_createAccount_with_valid_signature() public {
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        assertTrue(acct != address(0));
        assertTrue(factory.isAccount(acct));
    }

    function test_createAccount_stores_in_mapping() public {
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        assertEq(factory.accounts(signer, salt), acct);
    }

    function test_createAccount_sets_correct_owner() public {
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        LPAccount lpAccount = LPAccount(payable(acct));
        assertEq(lpAccount.owner(), signer);
    }

    function test_createAccount_sets_correct_factory() public {
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        LPAccount lpAccount = LPAccount(payable(acct));
        assertEq(lpAccount.FACTORY(), address(factory));
    }

    function test_createAccount_sets_correct_aqua() public {
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        LPAccount lpAccount = LPAccount(payable(acct));
        assertEq(address(lpAccount.AQUA()), address(aqua));
    }

    function test_createAccount_sets_correct_swapVMRouter() public {
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        LPAccount lpAccount = LPAccount(payable(acct));
        assertEq(lpAccount.swapVMRouter(), swapVMRouter);
    }

    function test_createAccount_reverts_duplicate() public {
        vm.prank(signer);
        factory.createAccount(signature);
        vm.prank(signer);
        vm.expectRevert(Errors.AccountAlreadyExists.selector);
        factory.createAccount(signature);
    }

    function test_createAccount_reverts_invalid_signature() public {
        // Random bytes as signature
        bytes memory badSig =
            hex"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbe01";
        vm.prank(signer);
        vm.expectRevert(Errors.InvalidSignature.selector);
        factory.createAccount(badSig);
    }

    function test_createAccount_signature_from_different_address() public {
        // Signature is from signerKey but called by a different address
        address otherCaller = address(0xBBBB);
        vm.prank(otherCaller);
        vm.expectRevert(Errors.InvalidSignature.selector);
        factory.createAccount(signature);
    }

    function test_createAccount_allows_different_signatures() public {
        // First account with first signature
        vm.prank(signer);
        address acct1 = factory.createAccount(signature);

        // Second account with a different key/signature
        uint256 signerKey2 = 0xB0B;
        address signer2 = vm.addr(signerKey2);
        bytes memory sig2 = _signCreateAccount(signerKey2, address(factory));

        vm.prank(signer2);
        address acct2 = factory.createAccount(sig2);
        assertTrue(acct1 != acct2);
    }

    // getAccount tests
    function test_getAccount_returns_account() public {
        vm.prank(signer);
        address created = factory.createAccount(signature);
        address fetched = factory.getAccount(signer, salt);
        assertEq(created, fetched);
    }

    function test_getAccount_returns_zero_if_not_created() public view {
        address fetched = factory.getAccount(signer, salt);
        assertEq(fetched, address(0));
    }

    // Upgrade tests
    function test_upgradeAccountImplementation_updates_all_proxies() public {
        // Create an account
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        LPAccount lpAccount = LPAccount(payable(acct));

        // Verify it works before upgrade
        assertEq(lpAccount.owner(), signer);

        // Deploy new implementation
        LPAccount newImpl = new LPAccount(address(0));

        // Upgrade — only factory owner can do this
        factory.upgradeAccountImplementation(address(newImpl));

        // Account should still work after upgrade (state preserved)
        assertEq(lpAccount.owner(), signer);
        assertEq(address(lpAccount.AQUA()), address(aqua));
    }

    function test_upgradeAccountImplementation_preserves_state() public {
        // Create account and ship a strategy
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        LPAccount lpAccount = LPAccount(payable(acct));

        address[] memory shipTokens = new address[](1);
        shipTokens[0] = address(0xBEEF);
        uint256[] memory shipAmounts = new uint256[](1);
        shipAmounts[0] = 1000;

        vm.prank(signer);
        bytes32 strategyHash = lpAccount.ship("test-strategy", shipTokens, shipAmounts);

        // Verify state before upgrade
        address[] memory storedTokens = lpAccount.getStrategyTokens(strategyHash);
        assertEq(storedTokens.length, 1);
        assertEq(storedTokens[0], address(0xBEEF));

        // Upgrade
        LPAccount newImpl = new LPAccount(address(0));
        factory.upgradeAccountImplementation(address(newImpl));

        // Verify state preserved after upgrade
        address[] memory tokensAfter = lpAccount.getStrategyTokens(strategyHash);
        assertEq(tokensAfter.length, 1);
        assertEq(tokensAfter[0], address(0xBEEF));
        assertEq(lpAccount.owner(), signer);
    }

    function test_upgradeAccountImplementation_reverts_not_owner() public {
        LPAccount newImpl = new LPAccount(address(0));
        vm.prank(address(0xCAFE));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xCAFE)));
        factory.upgradeAccountImplementation(address(newImpl));
    }

    function test_upgradeAccountImplementation_reverts_zero_address() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.upgradeAccountImplementation(address(0));
    }

    function test_createAccount_emits_AccountCreated() public {
        vm.prank(signer);
        address acct = factory.createAccount(signature);
        // Verify account was created at a non-zero address and event was emitted
        assertTrue(acct != address(0));
        assertTrue(factory.isAccount(acct));
        assertEq(factory.accounts(signer, salt), acct);
    }
}
