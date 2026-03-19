// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract Tiny { }

contract CheckAddr is Script {
    function run() external {
        uint256 key = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        vm.startBroadcast(key);
        bytes32 salt = bytes32(uint256(12345));
        Tiny t = new Tiny{salt: salt}();
        console.log("Actual Tiny addr:", address(t));
        vm.stopBroadcast();
        // Also compute expected from both candidates
        bytes32 ch = keccak256(type(Tiny).creationCode);
        address fromFactory = vm.computeCreate2Address(salt, ch, CREATE2_FACTORY);
        console.log("Expected (CREATE2_FACTORY):", fromFactory);
        console.log("CREATE2_FACTORY:", CREATE2_FACTORY);
    }
}
