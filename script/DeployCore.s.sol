// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TODO This
import {Script} from "forge-std/Script.sol";
import "../src/Core.sol";
import "../src/Room.sol";

contract DeployCore is Script {
    function run() external returns (address) {
        vm.startBroadcast();

        // Deploy Room implementation - no constructor args needed now
        Room roomImpl = new Room();

        // Deploy Core with USDC address
        Core core = new Core(address(0)); // Replace with actual USDC address

        // Set Room implementation in Core
        core.setRoomImplementation(address(roomImpl));

        vm.stopBroadcast();

        return address(core);
    }
}
