// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Room} from "../src/Room.sol";

contract RecordDecisionsAndStartRound is Script {
    // Update this with your deployed room address
    address constant ROOM_ADDRESS = 0x822543BE8732D116821bD51eCa7616F6b3bD5575;

    // Known agent addresses
    address constant TARGET_1 = 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d;
    address constant TARGET_2 = 0x830598617569AfD7Ad16343f5D4a226578b16A3d;
    address constant TARGET_3 = 0x1D5EbEABEE35dbBA6Fd2847401F979b3f6249a93;

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        Room room = Room(payable(ROOM_ADDRESS));

        // Print current round state
        uint256 currentRoundId = room.currentRoundId();
        console2.log("\nCurrent round:", currentRoundId);
        console2.log("Round state:", uint8(room.getRoundState(currentRoundId)));

        // Submit decisions for each agent
        console2.log("\nSubmitting agent decisions...");

        // Submit random decisions for each agent
        address[3] memory agents = [TARGET_1, TARGET_2, TARGET_3];
        Room.BetType[3] memory decisions = [Room.BetType.BUY, Room.BetType.HOLD, Room.BetType.SELL];

        for (uint256 i = 0; i < agents.length; i++) {
            // Use block.timestamp + agent address to generate pseudo-random decision
            uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, agents[i]))) % 3;
            Room.BetType decision = decisions[randomIndex];

            try room.submitAgentDecision(agents[i], decision) {
                console2.log(
                    string.concat(
                        "Decision submitted for agent ",
                        vm.toString(agents[i]),
                        ": ",
                        decision == Room.BetType.BUY ? "BUY" : decision == Room.BetType.HOLD ? "HOLD" : "SELL"
                    )
                );
            } catch Error(string memory reason) {
                console2.log("Error submitting decision:", reason);
            }
        }

        room.setCurrentRoundState(Room.RoundState.CLOSED);

        // Start new round
        console2.log("\nStarting new round...");
        try room.startRound() {
            console2.log("New round started successfully");

            // Print new round info
            uint256 newRoundId = room.currentRoundId();
            console2.log("New round ID:", newRoundId);
            console2.log("New round state:", uint8(room.getRoundState(newRoundId)));
            console2.log("Round start time:", room.getRoundStartTime(newRoundId));
            console2.log("Round end time:", room.getRoundEndTime(newRoundId));
        } catch Error(string memory reason) {
            console2.log("Error starting new round:", reason);
        }

        vm.stopBroadcast();
    }
}
