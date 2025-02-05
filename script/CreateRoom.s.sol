// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Core} from "../src/Core.sol";
import {Room} from "../src/Room.sol";

contract CreateRoom is Script {
    function run(address coreAddress, address tokenAddress, address[] memory agents) public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        Core core = Core(payable(coreAddress));

        vm.startBroadcast(deployerPrivateKey);
        // Get the fees from core contract
        (uint256 roomCreationFee, uint256 agentCreationFee, uint256 minBet, uint256 treasuryFee, uint256 referralFee) = core.getFees();
        // Create room with the correct fee
        address roomAddress = core.createRoom{value: roomCreationFee}(tokenAddress, agents);
        vm.stopBroadcast();

        return roomAddress;
    }
}
