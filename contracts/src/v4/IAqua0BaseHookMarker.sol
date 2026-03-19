// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IAqua0BaseHookMarker
/// @notice Interface to uniquely identify Aqua0 compatible hooks via ERC165
interface IAqua0BaseHookMarker is IERC165 {
    /// @notice Returns true if the contract is an Aqua0 Base Hook
    function isAqua0BaseHook() external pure returns (bool);
}
