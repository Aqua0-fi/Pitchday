// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { StargateAdapter } from "../src/bridge/StargateAdapter.sol";
import { Composer } from "../src/bridge/Composer.sol";
import { IAccount } from "../src/interface/IAccount.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {
    IStargate,
    SendParam,
    MessagingFee as SgMessagingFee,
    MessagingReceipt as SgMessagingReceipt
} from "../src/interface/IStargate.sol";
import { Errors } from "../src/lib/Errors.sol";
import { Events } from "../src/lib/Events.sol";

// Mock Stargate Pool
contract MockStargate is IStargate {
    uint64 public nonceCounter;
    bytes32 public lastGuid;
    address public immutable tokenAddress;
    bytes public lastExtraOptions;
    bytes public lastComposeMsg;

    error InsufficientFee();

    constructor(address _token) {
        tokenAddress = _token;
    }

    function send(SendParam calldata _sendParam, SgMessagingFee calldata _fee, address)
        external
        payable
        override
        returns (SgMessagingReceipt memory receipt, uint256 amountOut)
    {
        if (msg.value < _fee.nativeFee) revert InsufficientFee();
        // Pull tokens from the adapter (simulates real Stargate pool behavior)
        MockToken(tokenAddress).transferFrom(msg.sender, address(this), _sendParam.amountLD);
        nonceCounter++;
        lastGuid = keccak256(abi.encode(_sendParam.dstEid, _sendParam.to, nonceCounter));
        lastExtraOptions = _sendParam.extraOptions;
        lastComposeMsg = _sendParam.composeMsg;
        receipt = SgMessagingReceipt({ guid: lastGuid, nonce: nonceCounter, fee: _fee });
        amountOut = _sendParam.amountLD; // Simplified: no slippage in mock
    }

    function quoteSend(SendParam calldata, bool) external pure override returns (SgMessagingFee memory fee) {
        fee = SgMessagingFee({ nativeFee: 0.02 ether, lzTokenFee: 0 });
    }

    function token() external view override returns (address) {
        return tokenAddress;
    }
}

// Minimal ERC20 for Stargate tests
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

contract StargateAdapterTest is Test {
    MockToken public token;
    MockStargate public stargate;
    StargateAdapter public adapter;

    address public owner = address(this);
    uint32 public constant ARB_EID = 30110;

    function setUp() public {
        token = new MockToken();
        stargate = new MockStargate(address(token));
        adapter = new StargateAdapter(owner);
        adapter.registerPool(address(token), address(stargate));
    }

    // Constructor tests
    function test_constructor_sets_owner() public view {
        assertEq(adapter.owner(), owner);
    }

    function test_constructor_reverts_zero_owner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new StargateAdapter(address(0));
    }

    // registerPool tests
    function test_registerPool_sets_pool() public view {
        assertEq(adapter.getPool(address(token)), address(stargate));
    }

    function test_registerPool_emits_event() public {
        MockToken newToken = new MockToken();
        MockStargate newStargate = new MockStargate(address(newToken));
        vm.expectEmit(true, true, false, false);
        emit Events.StargatePoolRegistered(address(newToken), address(newStargate));
        adapter.registerPool(address(newToken), address(newStargate));
    }

    function test_registerPool_reverts_zero_token() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        adapter.registerPool(address(0), address(stargate));
    }

    function test_registerPool_reverts_zero_pool() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        adapter.registerPool(address(0x1234), address(0));
    }

    function test_registerPool_reverts_duplicate() public {
        vm.expectRevert(Errors.PoolAlreadyRegistered.selector);
        adapter.registerPool(address(token), address(0x9999));
    }

    function test_registerPool_reverts_not_owner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBEEF)));
        adapter.registerPool(address(0x1234), address(0x5678));
    }

    // removePool tests
    function test_removePool_clears_pool() public {
        adapter.removePool(address(token));
        assertEq(adapter.getPool(address(token)), address(0));
    }

    function test_removePool_emits_event() public {
        vm.expectEmit(true, true, false, false);
        emit Events.StargatePoolRemoved(address(token), address(stargate));
        adapter.removePool(address(token));
    }

    function test_removePool_reverts_zero_token() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        adapter.removePool(address(0));
    }

    function test_removePool_reverts_not_registered() public {
        vm.expectRevert(Errors.PoolNotRegistered.selector);
        adapter.removePool(address(0x9999));
    }

    function test_removePool_reverts_not_owner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBEEF)));
        adapter.removePool(address(token));
    }

    function test_removePool_updates_registered_tokens() public {
        address[] memory before = adapter.getRegisteredTokens();
        assertEq(before.length, 1);

        adapter.removePool(address(token));

        address[] memory after_ = adapter.getRegisteredTokens();
        assertEq(after_.length, 0);
    }

    // getRegisteredTokens tests
    function test_getRegisteredTokens_returns_all() public {
        MockToken token2 = new MockToken();
        MockStargate stargate2 = new MockStargate(address(token2));
        adapter.registerPool(address(token2), address(stargate2));

        address[] memory tokens = adapter.getRegisteredTokens();
        assertEq(tokens.length, 2);
    }

    // quoteBridgeFee tests
    function test_quoteBridgeFee_returns_fee() public view {
        address recipient = address(0xBEEF);
        uint256 amount = 1000 ether;
        uint256 minAmount = 990 ether;

        uint256 fee = adapter.quoteBridgeFee(address(token), ARB_EID, recipient, amount, minAmount);
        assertEq(fee, 0.02 ether);
    }

    function test_quoteBridgeFee_reverts_unregistered_token() public {
        vm.expectRevert(Errors.PoolNotRegistered.selector);
        adapter.quoteBridgeFee(address(0x9999), ARB_EID, address(0xBEEF), 1000, 990);
    }

    // bridge tests
    function test_bridge_sends_tokens() public {
        address recipient = address(0xBEEF);
        uint256 amount = 1000 ether;
        uint256 minAmount = 990 ether;

        token.mint(address(this), amount);
        token.approve(address(adapter), amount);

        uint256 fee = adapter.quoteBridgeFee(address(token), ARB_EID, recipient, amount, minAmount);

        bytes32 guid = adapter.bridge{ value: fee }(address(token), ARB_EID, recipient, amount, minAmount);
        assertTrue(guid != bytes32(0));
    }

    function test_bridge_reverts_zero_amount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, address(0xBEEF), 0, 0);
    }

    function test_bridge_reverts_zero_recipient() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, address(0), 1000, 990);
    }

    function test_bridge_reverts_unregistered_token() public {
        vm.expectRevert(Errors.PoolNotRegistered.selector);
        adapter.bridge{ value: 0.02 ether }(address(0x9999), ARB_EID, address(0xBEEF), 1000, 990);
    }

    // bridgeWithCompose tests
    function test_bridgeWithCompose_sends_with_payload() public {
        address composerAddr = address(0xCAFE);
        uint256 amount = 500 ether;
        uint256 minAmount = 490 ether;
        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("strategy"), new address[](0), new uint256[](0));

        token.mint(address(this), amount);
        token.approve(address(adapter), amount);

        uint256 fee = adapter.quoteBridgeFee(address(token), ARB_EID, composerAddr, amount, minAmount);

        bytes32 guid = adapter.bridgeWithCompose{ value: fee }(
            address(token), ARB_EID, composerAddr, composeMsg, amount, minAmount, 128_000, 200_000
        );

        assertTrue(guid != bytes32(0));
    }

    function test_bridgeWithCompose_reverts_zero_amount() public {
        bytes memory composeMsg = "";
        vm.expectRevert(Errors.ZeroAmount.selector);
        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token), ARB_EID, address(0xCAFE), composeMsg, 0, 0, 128_000, 200_000
        );
    }

    function test_bridgeWithCompose_reverts_zero_composer() public {
        bytes memory composeMsg = "";
        vm.expectRevert(Errors.ZeroAddress.selector);
        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token), ARB_EID, address(0), composeMsg, 1000, 990, 128_000, 200_000
        );
    }

    function test_bridgeWithCompose_reverts_unregistered_token() public {
        bytes memory composeMsg = "";
        vm.expectRevert(Errors.PoolNotRegistered.selector);
        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(0x9999), ARB_EID, address(0xCAFE), composeMsg, 1000, 990, 128_000, 200_000
        );
    }

    function test_receive_accepts_eth() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = payable(address(adapter)).call{ value: 1 ether }("");
        assertTrue(success);
        assertEq(address(adapter).balance, 1 ether);
    }

    // ============================================
    // StargateAdapter compose option tests
    // ============================================

    function test_bridgeWithCompose_builds_type3_options() public {
        address composerAddr = address(0xCAFE);
        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("s"), new address[](0), new uint256[](0));

        token.mint(address(this), 100 ether);
        token.approve(address(adapter), 100 ether);

        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token), ARB_EID, composerAddr, composeMsg, 100 ether, 99 ether, 128_000, 200_000
        );

        // Verify extraOptions were passed to Stargate
        bytes memory opts = stargate.lastExtraOptions();
        assertTrue(opts.length > 0, "extraOptions should not be empty");
        // First two bytes should be TYPE_3 (0x0003)
        assertEq(uint16(bytes2(abi.encodePacked(opts[0], opts[1]))), 0x0003);
    }

    function test_bridgeWithCompose_reverts_zero_composeGas() public {
        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("s"), new address[](0), new uint256[](0));
        vm.expectRevert(Errors.InvalidInput.selector);
        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token), ARB_EID, address(0xCAFE), composeMsg, 100 ether, 99 ether, 128_000, 0
        );
    }

    function test_quoteBridgeWithComposeFee() public view {
        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("s"), new address[](0), new uint256[](0));
        uint256 fee = adapter.quoteBridgeWithComposeFee(
            address(token), ARB_EID, address(0xCAFE), composeMsg, 100 ether, 99 ether, 128_000, 200_000
        );
        assertEq(fee, 0.02 ether); // Mock returns same fee for any params
    }

    function testFuzz_bridgeWithCompose_gas_params(uint128 _receiveGas, uint128 _composeGas) public {
        _composeGas = uint128(bound(uint256(_composeGas), 1, type(uint128).max));
        _receiveGas = uint128(bound(uint256(_receiveGas), 0, type(uint128).max));

        token.mint(address(this), 100 ether);
        token.approve(address(adapter), 100 ether);

        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("s"), new address[](0), new uint256[](0));
        bytes32 guid = adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token), ARB_EID, address(0xCAFE), composeMsg, 100 ether, 99 ether, _receiveGas, _composeGas
        );
        assertTrue(guid != bytes32(0));
    }

    function test_bridge_passes_empty_extraOptions() public {
        token.mint(address(this), 100 ether);
        token.approve(address(adapter), 100 ether);

        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, address(0xBEEF), 100 ether, 99 ether);

        // Simple bridge should pass empty extraOptions
        bytes memory opts = stargate.lastExtraOptions();
        assertEq(opts.length, 0, "simple bridge should have empty extraOptions");
    }

    // ============================================
    // TOKEN PULL TESTS
    // ============================================

    function test_bridge_pulls_tokens_from_caller() public {
        address recipient = address(0xBEEF);
        uint256 amount = 100 ether;

        token.mint(address(this), amount);
        token.approve(address(adapter), amount);

        uint256 callerBefore = token.balanceOf(address(this));
        uint256 stargateBefore = token.balanceOf(address(stargate));

        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, recipient, amount, 99 ether);

        uint256 callerAfter = token.balanceOf(address(this));
        uint256 stargateAfter = token.balanceOf(address(stargate));

        assertEq(callerBefore - callerAfter, amount, "caller should have lost tokens");
        assertEq(stargateAfter - stargateBefore, amount, "stargate should have received tokens");
        // Adapter should hold zero tokens (pulled from caller, approved to stargate, stargate pulled)
        assertEq(token.balanceOf(address(adapter)), 0, "adapter should hold zero tokens");
    }

    function test_bridgeWithCompose_pulls_tokens_from_caller() public {
        address composerAddr = address(0xCAFE);
        uint256 amount = 200 ether;
        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("strategy"), new address[](0), new uint256[](0));

        token.mint(address(this), amount);
        token.approve(address(adapter), amount);

        uint256 callerBefore = token.balanceOf(address(this));
        uint256 stargateBefore = token.balanceOf(address(stargate));

        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token), ARB_EID, composerAddr, composeMsg, amount, 190 ether, 128_000, 200_000
        );

        uint256 callerAfter = token.balanceOf(address(this));
        uint256 stargateAfter = token.balanceOf(address(stargate));

        assertEq(callerBefore - callerAfter, amount, "caller should have lost tokens");
        assertEq(stargateAfter - stargateBefore, amount, "stargate should have received tokens");
        assertEq(token.balanceOf(address(adapter)), 0, "adapter should hold zero tokens");
    }

    function test_bridge_reverts_insufficient_allowance() public {
        uint256 amount = 100 ether;
        token.mint(address(this), amount);
        // No approval — should revert

        vm.expectRevert();
        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, address(0xBEEF), amount, 99 ether);
    }

    function test_bridgeWithCompose_captures_compose_payload() public {
        address composerAddr = address(0xCAFE);
        uint256 amount = 50 ether;
        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("my_strategy"), new address[](0), new uint256[](0));

        token.mint(address(this), amount);
        token.approve(address(adapter), amount);

        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token), ARB_EID, composerAddr, composeMsg, amount, 49 ether, 128_000, 200_000
        );

        bytes memory captured = stargate.lastComposeMsg();
        assertEq(keccak256(captured), keccak256(composeMsg), "compose payload should be captured by mock stargate");
    }

    // ============================================
    // MULTI-TOKEN ROUTING TESTS
    // ============================================

    function test_multi_token_bridge_routes_correctly() public {
        // Register a second token/pool
        MockToken token2 = new MockToken();
        MockStargate stargate2 = new MockStargate(address(token2));
        adapter.registerPool(address(token2), address(stargate2));

        // Bridge token1 → should use stargate1
        token.mint(address(this), 100 ether);
        token.approve(address(adapter), 100 ether);
        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, address(0xBEEF), 100 ether, 99 ether);
        assertTrue(stargate.lastGuid() != bytes32(0), "stargate1 should have been called");
        assertEq(stargate2.lastGuid(), bytes32(0), "stargate2 should NOT have been called");

        // Bridge token2 → should use stargate2
        token2.mint(address(this), 50 ether);
        token2.approve(address(adapter), 50 ether);
        adapter.bridge{ value: 0.02 ether }(address(token2), ARB_EID, address(0xBEEF), 50 ether, 49 ether);
        assertTrue(stargate2.lastGuid() != bytes32(0), "stargate2 should have been called");
    }

    function test_multi_token_bridgeWithCompose_routes_correctly() public {
        MockToken token2 = new MockToken();
        MockStargate stargate2 = new MockStargate(address(token2));
        adapter.registerPool(address(token2), address(stargate2));

        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("s"), new address[](0), new uint256[](0));

        // BridgeWithCompose token2
        token2.mint(address(this), 100 ether);
        token2.approve(address(adapter), 100 ether);
        adapter.bridgeWithCompose{ value: 0.02 ether }(
            address(token2), ARB_EID, address(0xCAFE), composeMsg, 100 ether, 99 ether, 128_000, 200_000
        );
        assertTrue(stargate2.lastGuid() != bytes32(0), "stargate2 should have been called for compose");
    }

    function test_remove_pool_then_bridge_reverts() public {
        adapter.removePool(address(token));

        token.mint(address(this), 100 ether);
        token.approve(address(adapter), 100 ether);

        vm.expectRevert(Errors.PoolNotRegistered.selector);
        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, address(0xBEEF), 100 ether, 99 ether);
    }

    function test_re_register_pool_after_remove() public {
        adapter.removePool(address(token));
        assertEq(adapter.getPool(address(token)), address(0));

        // Re-register with a new pool
        MockStargate newStargate = new MockStargate(address(token));
        adapter.registerPool(address(token), address(newStargate));
        assertEq(adapter.getPool(address(token)), address(newStargate));

        // Bridge should use the new pool
        token.mint(address(this), 100 ether);
        token.approve(address(adapter), 100 ether);
        adapter.bridge{ value: 0.02 ether }(address(token), ARB_EID, address(0xBEEF), 100 ether, 99 ether);
        assertTrue(newStargate.lastGuid() != bytes32(0), "new stargate should have been called");
    }

    // receive ETH for refunds
    receive() external payable { }
}

// ============================================
// Mock WETH for native pool tests
// ============================================

contract MockWETH {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient WETH balance");
        balanceOf[msg.sender] -= amount;
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "ETH transfer failed");
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

// Mock native Stargate pool (token() returns address(0))
contract MockNativeStargate is IStargate {
    uint64 public nonceCounter;
    bytes32 public lastGuid;
    bytes public lastExtraOptions;
    bytes public lastComposeMsg;
    uint256 public lastNativeFee;

    function send(SendParam calldata _sendParam, SgMessagingFee calldata _fee, address)
        external
        payable
        override
        returns (SgMessagingReceipt memory receipt, uint256 amountOut)
    {
        // Native pool validates: msg.value == amountLD + nativeFee
        uint256 required = _sendParam.amountLD + _fee.nativeFee;
        require(msg.value == required, "msg.value != amount + nativeFee");
        nonceCounter++;
        lastGuid = keccak256(abi.encode(_sendParam.dstEid, _sendParam.to, nonceCounter));
        lastExtraOptions = _sendParam.extraOptions;
        lastComposeMsg = _sendParam.composeMsg;
        lastNativeFee = _fee.nativeFee;
        receipt = SgMessagingReceipt({ guid: lastGuid, nonce: nonceCounter, fee: _fee });
        amountOut = _sendParam.amountLD;
    }

    function quoteSend(SendParam calldata, bool) external pure override returns (SgMessagingFee memory fee) {
        fee = SgMessagingFee({ nativeFee: 0.001 ether, lzTokenFee: 0 });
    }

    function token() external pure override returns (address) {
        return address(0); // Native ETH pool
    }

    receive() external payable { }
}

// ============================================
// Native ETH Pool Tests
// ============================================

contract StargateAdapterNativePoolTest is Test {
    MockWETH public weth;
    MockNativeStargate public nativeStargate;
    StargateAdapter public adapter;

    address public owner = address(this);
    uint32 public constant ARB_EID = 30110;

    function setUp() public {
        weth = new MockWETH();
        nativeStargate = new MockNativeStargate();
        adapter = new StargateAdapter(owner);
        adapter.registerPool(address(weth), address(nativeStargate));
    }

    /// @dev Helper: mint WETH to this contract and fund with ETH for msg.value.
    ///      The caller (test contract) needs WETH for the adapter to pull, and separate ETH for msg.value.
    function _fundForNativeBridge(uint256 amount, uint256 lzFee) internal {
        // Mint WETH by depositing ETH, then re-fund ETH for the msg.value
        vm.deal(address(this), amount);
        weth.deposit{ value: amount }();
        vm.deal(address(this), amount + lzFee); // re-fund: amount (for native pool) + lzFee
        weth.approve(address(adapter), amount);
    }

    function test_native_bridge_unwraps_weth_and_sends() public {
        uint256 amount = 1 ether;
        uint256 lzFee = 0.001 ether;
        uint256 totalValue = amount + lzFee;

        _fundForNativeBridge(amount, lzFee);

        bytes32 guid =
            adapter.bridge{ value: totalValue }(address(weth), ARB_EID, address(0xBEEF), amount, amount * 95 / 100);
        assertTrue(guid != bytes32(0), "GUID should be non-zero");

        // Adapter should hold zero WETH and zero ETH
        assertEq(weth.balanceOf(address(adapter)), 0, "adapter should hold zero WETH");
    }

    function test_native_bridge_sets_correct_nativeFee() public {
        uint256 amount = 1 ether;
        uint256 lzFee = 0.001 ether;
        uint256 totalValue = amount + lzFee;

        _fundForNativeBridge(amount, lzFee);

        adapter.bridge{ value: totalValue }(address(weth), ARB_EID, address(0xBEEF), amount, amount * 95 / 100);

        // nativeFee should be just the LZ fee, not the full msg.value
        assertEq(nativeStargate.lastNativeFee(), lzFee, "nativeFee should be lzFee only");
    }

    function test_native_bridgeWithCompose_unwraps_and_sends() public {
        uint256 amount = 0.5 ether;
        uint256 lzFee = 0.001 ether;
        uint256 totalValue = amount + lzFee;

        _fundForNativeBridge(amount, lzFee);

        bytes memory composeMsg = abi.encode(address(0xDEAD), bytes("strategy"), new address[](0), new uint256[](0));

        bytes32 guid = adapter.bridgeWithCompose{ value: totalValue }(
            address(weth), ARB_EID, address(0xCAFE), composeMsg, amount, amount * 95 / 100, 128_000, 200_000
        );
        assertTrue(guid != bytes32(0), "GUID should be non-zero");

        // nativeFee should be just the LZ fee
        assertEq(nativeStargate.lastNativeFee(), lzFee, "compose nativeFee should be lzFee only");
    }

    function test_native_bridge_sends_correct_msg_value_to_pool() public {
        uint256 amount = 2 ether;
        uint256 lzFee = 0.001 ether;
        uint256 totalValue = amount + lzFee;

        _fundForNativeBridge(amount, lzFee);

        adapter.bridge{ value: totalValue }(address(weth), ARB_EID, address(0xBEEF), amount, amount * 95 / 100);

        // Pool should have received the full ETH value (amount + fee)
        assertEq(address(nativeStargate).balance, totalValue, "pool should hold amount + fee as ETH");
    }

    function testFuzz_native_bridge_amount(uint128 _amount) public {
        uint256 amount = bound(uint256(_amount), 0.001 ether, 100 ether);
        uint256 lzFee = 0.001 ether;
        uint256 totalValue = amount + lzFee;

        _fundForNativeBridge(amount, lzFee);

        bytes32 guid = adapter.bridge{ value: totalValue }(
            address(weth), ARB_EID, address(0xBEEF), amount, amount * 95 / 100
        );
        assertTrue(guid != bytes32(0));
        assertEq(nativeStargate.lastNativeFee(), lzFee);
    }

    // receive ETH for refunds
    receive() external payable { }
}

// Simple mock Account for Composer tests
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

contract ComposerTest is Test {
    MockToken public token;
    Composer public composer;
    MockAccount public mockAccount;

    address public owner = address(this);
    address public lzEndpoint = address(this); // test uses self as lz endpoint
    address public stargatePool = address(0x5747);

    uint64 constant NONCE = 1;
    uint32 constant SRC_EID = 30184;

    function setUp() public {
        token = new MockToken();
        composer = new Composer(lzEndpoint, owner);
        composer.registerPool(stargatePool, address(token));
        mockAccount = new MockAccount();

        // Fund composer with tokens as if Stargate delivered them
        token.mint(address(composer), 1000 ether);
    }

    function _buildOFTMessage(uint256 amountLD, bytes memory appComposeMsg) internal pure returns (bytes memory) {
        return OFTComposeMsgCodec.encode(
            NONCE, SRC_EID, amountLD, abi.encodePacked(bytes32(uint256(uint160(address(0xABCD)))), appComposeMsg)
        );
    }

    function test_lzCompose_forwards_tokens_and_calls_account() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1000 ether;

        bytes memory strategyBytes = bytes("strategy");
        bytes memory composeMsg = abi.encode(address(mockAccount), strategyBytes, tokens, amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);

        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");

        // Tokens moved from composer to account
        assertEq(token.balanceOf(address(composer)), 0);
        assertEq(token.balanceOf(address(mockAccount)), 1000 ether);

        // Account hook called with correct data
        assertTrue(mockAccount.called());
        assertEq(keccak256(mockAccount.lastStrategyBytes()), keccak256(strategyBytes));
    }

    function test_lzCompose_reverts_if_not_endpoint() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1000 ether;

        bytes memory strategyBytes = bytes("strategy");
        bytes memory composeMsg = abi.encode(address(mockAccount), strategyBytes, tokens, amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);

        // Call from a different address
        vm.prank(address(0xDEAD));
        vm.expectRevert(Errors.NotAuthorized.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_constructor_reverts_zero_lzEndpoint() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new Composer(address(0), owner);
    }

    function test_constructor_reverts_zero_owner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Composer(lzEndpoint, address(0));
    }

    function test_constructor_sets_initial_values() public view {
        assertEq(composer.LZ_ENDPOINT(), lzEndpoint);
    }

    function test_lzCompose_reverts_zero_amount() public {
        bytes memory composeMsg =
            abi.encode(address(mockAccount), bytes("strategy"), new address[](1), new uint256[](1));
        bytes memory oftMsg = _buildOFTMessage(0, composeMsg);
        vm.expectRevert(Errors.ZeroAmount.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_empty_composeMsg() public {
        bytes memory oftMsg = _buildOFTMessage(1000 ether, "");
        vm.expectRevert(Errors.InvalidInput.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_zero_account_in_payload() public {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(0xBEEF);
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1000 ether;
        bytes memory composeMsg = abi.encode(address(0), bytes("strategy"), _tokens, _amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);
        vm.expectRevert(Errors.ZeroAddress.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_empty_strategy_in_payload() public {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(0xBEEF);
        uint256[] memory _amounts = new uint256[](1);
        _amounts[0] = 1000 ether;
        bytes memory composeMsg = abi.encode(address(mockAccount), bytes(""), _tokens, _amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);
        vm.expectRevert(Errors.InvalidStrategyBytes.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_empty_tokens_in_payload() public {
        address[] memory emptyTokens = new address[](0);
        uint256[] memory emptyAmounts = new uint256[](0);
        bytes memory composeMsg = abi.encode(address(mockAccount), bytes("strategy"), emptyTokens, emptyAmounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);
        vm.expectRevert(Errors.InvalidInput.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_mismatched_arrays_in_payload() public {
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(0xBEEF);
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 500 ether;
        _amounts[1] = 500 ether;
        bytes memory composeMsg = abi.encode(address(mockAccount), bytes("strategy"), _tokens, _amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);
        vm.expectRevert(Errors.InvalidInput.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    function test_lzCompose_reverts_unregistered_pool() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1000 ether;
        bytes memory composeMsg = abi.encode(address(mockAccount), bytes("strategy"), tokens, amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);

        vm.expectRevert(Errors.PoolNotRegistered.selector);
        composer.lzCompose(address(0xBAD), bytes32(uint256(1)), oftMsg, address(0), "");
    }

    // ============================================
    // COMPOSER POOL REGISTRY TESTS
    // ============================================

    function test_registerPool_sets_token() public view {
        assertEq(composer.getToken(stargatePool), address(token));
    }

    function test_registerPool_emits_event() public {
        address newPool = address(0x8888);
        MockToken newToken = new MockToken();
        vm.expectEmit(true, true, false, false);
        emit Events.ComposerPoolRegistered(newPool, address(newToken));
        composer.registerPool(newPool, address(newToken));
    }

    function test_registerPool_reverts_zero_pool() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        composer.registerPool(address(0), address(token));
    }

    function test_registerPool_reverts_zero_token() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        composer.registerPool(address(0x8888), address(0));
    }

    function test_registerPool_reverts_duplicate() public {
        vm.expectRevert(Errors.PoolAlreadyRegistered.selector);
        composer.registerPool(stargatePool, address(0x1234));
    }

    function test_registerPool_reverts_not_owner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBEEF)));
        composer.registerPool(address(0x8888), address(0x9999));
    }

    function test_removePool_clears_token() public {
        composer.removePool(stargatePool);
        assertEq(composer.getToken(stargatePool), address(0));
    }

    function test_removePool_emits_event() public {
        vm.expectEmit(true, true, false, false);
        emit Events.ComposerPoolRemoved(stargatePool, address(token));
        composer.removePool(stargatePool);
    }

    function test_removePool_reverts_zero_pool() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        composer.removePool(address(0));
    }

    function test_removePool_reverts_not_registered() public {
        vm.expectRevert(Errors.PoolNotRegistered.selector);
        composer.removePool(address(0x9999));
    }

    function test_removePool_reverts_not_owner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBEEF)));
        composer.removePool(stargatePool);
    }

    function test_removePool_updates_registered_pools() public {
        address[] memory before = composer.getRegisteredPools();
        assertEq(before.length, 1);

        composer.removePool(stargatePool);

        address[] memory after_ = composer.getRegisteredPools();
        assertEq(after_.length, 0);
    }

    function test_getRegisteredPools_returns_all() public {
        address newPool = address(0x8888);
        MockToken newToken = new MockToken();
        composer.registerPool(newPool, address(newToken));

        address[] memory pools = composer.getRegisteredPools();
        assertEq(pools.length, 2);
    }

    // ============================================
    // COMPOSER SETTER TESTS: setLzEndpoint
    // ============================================

    function test_setLzEndpoint_updates_address() public {
        address newEndpoint = address(0x9999);
        composer.setLzEndpoint(newEndpoint);
        assertEq(composer.LZ_ENDPOINT(), newEndpoint);
    }

    function test_setLzEndpoint_reverts_zero_address() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        composer.setLzEndpoint(address(0));
    }

    function test_setLzEndpoint_reverts_not_owner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBEEF)));
        composer.setLzEndpoint(address(0x1234));
    }

    function test_setLzEndpoint_emits_event() public {
        address newEndpoint = address(0x9999);
        vm.expectEmit(true, true, false, false);
        emit Events.LzEndpointSet(lzEndpoint, newEndpoint);
        composer.setLzEndpoint(newEndpoint);
    }

    // ============================================
    // MULTI-TOKEN COMPOSE ROUTING TESTS
    // ============================================

    function test_multi_pool_compose_routes_token_correctly() public {
        // Register a second pool/token
        MockToken token2 = new MockToken();
        address pool2 = address(0x8888);
        composer.registerPool(pool2, address(token2));

        // Fund composer with token2
        token2.mint(address(composer), 500 ether);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(token2);
        amounts[0] = 500 ether;

        bytes memory composeMsg = abi.encode(address(mockAccount), bytes("strategy"), tokens, amounts);
        bytes memory oftMsg = _buildOFTMessage(500 ether, composeMsg);

        // lzCompose from pool2 should transfer token2
        composer.lzCompose(pool2, bytes32(uint256(1)), oftMsg, address(0), "");

        assertEq(token2.balanceOf(address(mockAccount)), 500 ether, "account should receive token2");
        assertTrue(mockAccount.called());
    }

    function test_remove_pool_then_compose_reverts() public {
        composer.removePool(stargatePool);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1000 ether;
        bytes memory composeMsg = abi.encode(address(mockAccount), bytes("strategy"), tokens, amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);

        vm.expectRevert(Errors.PoolNotRegistered.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
    }

    // ============================================
    // FUNCTIONAL TESTS: Updated addresses in lzCompose
    // ============================================

    function test_lzCompose_uses_updated_lzEndpoint() public {
        address newEndpoint = address(0x9999);
        composer.setLzEndpoint(newEndpoint);

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(0xBEEF);
        amounts[0] = 1000 ether;

        bytes memory composeMsg = abi.encode(address(mockAccount), bytes("strategy"), tokens, amounts);
        bytes memory oftMsg = _buildOFTMessage(1000 ether, composeMsg);

        // New endpoint works
        vm.prank(newEndpoint);
        composer.lzCompose(stargatePool, bytes32(uint256(1)), oftMsg, address(0), "");
        assertTrue(mockAccount.called());

        // Old endpoint reverts
        vm.prank(lzEndpoint);
        vm.expectRevert(Errors.NotAuthorized.selector);
        composer.lzCompose(stargatePool, bytes32(uint256(2)), oftMsg, address(0), "");
    }
}
