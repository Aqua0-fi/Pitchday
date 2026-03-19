// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Composer } from "../src/bridge/Composer.sol";
import { IAccount } from "../src/interface/IAccount.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";

// Minimal ERC20 mock
contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(balanceOf[from] >= amount, "Insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// Simple mock Account
contract MockAccount is IAccount {
    bool public called;
    bytes public lastStrategyBytes;
    address[] public lastTokens;
    uint256[] public lastAmounts;

    function onCrosschainDeposit(bytes memory strategyBytes, address[] memory tokens, uint256[] memory amounts)
        external
        override
        returns (bytes32)
    {
        called = true;
        lastStrategyBytes = strategyBytes;
        lastTokens = tokens;
        lastAmounts = amounts;
        return keccak256(strategyBytes);
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

// Mock account that reverts
contract RevertingAccount is IAccount {
    function onCrosschainDeposit(bytes memory, address[] memory, uint256[] memory)
        external
        pure
        override
        returns (bytes32)
    {
        revert("account reverted");
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

contract ComposerLzComposeTest is Test {
    MockToken public token;
    Composer public composer;
    MockAccount public mockAccount;

    address public owner = address(this);
    address public lzEndpoint = address(0xE1);
    address public stargate = address(0x5747);

    uint64 constant NONCE = 1;
    uint32 constant SRC_EID = 30184; // Base
    address constant COMPOSE_FROM = address(0xABCD);

    function setUp() public {
        token = new MockToken();
        composer = new Composer(lzEndpoint, owner);
        composer.registerPool(stargate, address(token));
        mockAccount = new MockAccount();

        // Fund composer with tokens as if Stargate delivered them
        token.mint(address(composer), 1000 ether);
    }

    // ============================================
    // HELPER: build OFT compose message
    // ============================================

    function _buildOFTMessage(uint256 amountLD, bytes memory appComposeMsg) internal pure returns (bytes memory) {
        return OFTComposeMsgCodec.encode(
            NONCE, SRC_EID, amountLD, abi.encodePacked(bytes32(uint256(uint160(COMPOSE_FROM))), appComposeMsg)
        );
    }

    function _buildAppComposeMsg(address _account, uint256 _amount) internal pure returns (bytes memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;
        return abi.encode(_account, bytes("strategy"), tokens, amounts);
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_sets_initial_values() public view {
        assertEq(composer.LZ_ENDPOINT(), lzEndpoint);
        assertEq(composer.owner(), owner);
        assertEq(composer.getToken(stargate), address(token));
    }

    function test_constructor_reverts_zero_lzEndpoint() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new Composer(address(0), owner);
    }

    function test_constructor_reverts_zero_owner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Composer(lzEndpoint, address(0));
    }

    // ============================================
    // CALLER VALIDATION TESTS
    // ============================================

    function test_lzCompose_reverts_if_not_lzEndpoint() public {
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 1000 ether);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(address(0xDEAD)); // not the LZ endpoint
        vm.expectRevert(Errors.NotAuthorized.selector);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_if_unregistered_pool() public {
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 1000 ether);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.PoolNotRegistered.selector);
        composer.lzCompose(address(0xBAD), bytes32(uint256(1)), oftMsg, address(0), "");
    }

    // ============================================
    // MESSAGE DECODING + TOKEN FORWARDING TESTS
    // ============================================

    function test_lzCompose_forwards_tokens_and_calls_account() public {
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 1000 ether);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");

        // Tokens moved from composer to account
        assertEq(token.balanceOf(address(composer)), 0);
        assertEq(token.balanceOf(address(mockAccount)), 1000 ether);

        // Account hook called
        assertTrue(mockAccount.called());
        assertEq(keccak256(mockAccount.lastStrategyBytes()), keccak256(bytes("strategy")));
    }

    function test_lzCompose_emits_ComposeReceived() public {
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 1000 ether);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);
        bytes32 guid = bytes32(uint256(42));

        vm.expectEmit(true, true, false, true);
        emit Events.ComposeReceived(guid, stargate, 1000 ether, keccak256(bytes("strategy")));

        vm.prank(lzEndpoint);
        composer.lzCompose(stargate, guid, oftMsg, address(0), "");
    }

    function test_lzCompose_decodes_amountLD_correctly() public {
        uint256 amount = 500 ether;
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), amount);
        bytes memory oftMsg = _buildOFTMessage(amount, appMsg);

        token.mint(address(composer), amount); // extra tokens to cover the 500 ether

        vm.prank(lzEndpoint);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");

        // Exactly 500 ether transferred to account (from the 1500 total balance)
        assertEq(token.balanceOf(address(mockAccount)), amount);
    }

    // ============================================
    // VALIDATION TESTS (via _handleCompose)
    // ============================================

    function test_lzCompose_reverts_zero_amount() public {
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 0);
        bytes memory oftMsg = _buildOFTMessage(0, appMsg);

        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.ZeroAmount.selector);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_empty_composeMsg() public {
        // Build OFT message with empty app compose msg
        bytes memory oftMsg = OFTComposeMsgCodec.encode(
            NONCE, SRC_EID, 1000 ether, abi.encodePacked(bytes32(uint256(uint160(COMPOSE_FROM))), "")
        );

        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.InvalidInput.selector);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_zero_account_in_payload() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1000 ether;
        bytes memory appMsg = abi.encode(address(0), bytes("strategy"), tokens, _amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.ZeroAddress.selector);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_empty_strategy() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1000 ether;
        bytes memory appMsg = abi.encode(address(mockAccount), bytes(""), tokens, _amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.InvalidStrategyBytes.selector);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_mismatched_arrays() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xBEEF);
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 500 ether;
        _amounts[1] = 500 ether;
        bytes memory appMsg = abi.encode(address(mockAccount), bytes("strategy"), tokens, _amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.InvalidInput.selector);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_empty_tokens() public {
        address[] memory emptyTokens = new address[](0);
        uint256[] memory emptyAmounts = new uint256[](0);
        bytes memory appMsg = abi.encode(address(mockAccount), bytes("strategy"), emptyTokens, emptyAmounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.InvalidInput.selector);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    function test_lzCompose_multiple_tokens_in_payload() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(0xBEEF);
        tokens[1] = address(0xCAFE);
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 500 ether;
        _amounts[1] = 500 ether;
        bytes memory appMsg = abi.encode(address(mockAccount), bytes("multi-strategy"), tokens, _amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");

        assertTrue(mockAccount.called());
        assertEq(token.balanceOf(address(mockAccount)), 1000 ether);
    }

    function test_lzCompose_accepts_eth_value() public {
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 1000 ether);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.deal(lzEndpoint, 1 ether);
        vm.prank(lzEndpoint);
        composer.lzCompose{ value: 0.5 ether }(stargate, bytes32(uint256(1)), oftMsg, address(0), "");

        assertTrue(mockAccount.called());
    }

    function test_lzCompose_receive_accepts_eth() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = payable(address(composer)).call{ value: 1 ether }("");
        assertTrue(success);
        assertEq(address(composer).balance, 1 ether);
    }

    function test_lzCompose_reverts_insufficient_balance() public {
        // Deploy a new composer with no token balance
        Composer emptyComposer = new Composer(lzEndpoint, owner);
        emptyComposer.registerPool(stargate, address(token));

        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 1000 ether);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, appMsg);

        vm.prank(lzEndpoint);
        vm.expectRevert(); // SafeERC20 transfer will revert
        emptyComposer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_lzCompose_amount(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint128).max);

        // Mint enough tokens
        token.mint(address(composer), _amount);

        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), _amount);
        bytes memory oftMsg = _buildOFTMessage(_amount, appMsg);

        vm.prank(lzEndpoint);
        composer.lzCompose(stargate, bytes32(uint256(1)), oftMsg, address(0), "");

        assertEq(token.balanceOf(address(mockAccount)), _amount);
        assertTrue(mockAccount.called());
    }

    function testFuzz_lzCompose_guid(bytes32 _guid) public {
        bytes memory appMsg = _buildAppComposeMsg(address(mockAccount), 100 ether);
        bytes memory oftMsg = _buildOFTMessage(100 ether, appMsg);

        vm.prank(lzEndpoint);
        composer.lzCompose(stargate, _guid, oftMsg, address(0), "");

        assertTrue(mockAccount.called());
    }
}
