// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TODO This
import {Script} from "forge-std/Script.sol";
import "../src/Core.sol";
import "../src/Room.sol";

contract DeployCore is Script {
    function run() external returns (address) {
        vm.startBroadcast();


        // Deploy Core with USDC address
        Core core = new Core(address(0)); // Replace with actual USDC address

        // Set Room implementation in Core

        vm.stopBroadcast();

        return address(core);
    }
}
