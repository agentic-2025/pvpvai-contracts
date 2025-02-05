// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Room} from "../src/Room.sol";

contract StartRound is Script {
    function run(address roomAddress) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        Room room = Room(roomAddress);

        vm.startBroadcast(deployerPrivateKey);
        room.startRound();
        vm.stopBroadcast();
    }
}
