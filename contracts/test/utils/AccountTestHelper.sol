// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Account } from "../../src/lp/Account.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @title AccountTestHelper
/// @notice Shared helper to reduce boilerplate across test files for deploying Account proxies
library AccountTestHelper {
    /// @notice Deploy an Account behind a BeaconProxy
    /// @param beacon The UpgradeableBeacon address
    /// @param owner The account owner
    /// @param factory The factory address
    /// @param aqua The Aqua protocol address
    /// @param swapVMRouter The SwapVM Router address
    /// @return The initialized Account proxy
    function deployAccountProxy(address beacon, address owner, address factory, address aqua, address swapVMRouter)
        internal
        returns (Account)
    {
        bytes memory initData = abi.encodeCall(Account.initialize, (owner, factory, aqua, swapVMRouter));
        BeaconProxy proxy = new BeaconProxy(beacon, initData);
        return Account(payable(address(proxy)));
    }
}
