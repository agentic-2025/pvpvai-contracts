// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import "../src/Room.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "forge-std/console2.sol";

// contract TestRoomActions is Script {
//     // Constants for target addresses
//     address constant TARGET_1 = 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d;
//     address constant TARGET_2 = 0x830598617569AfD7Ad16343f5D4a226578b16A3d;
//     address constant ROOM_ADDRESS = 0x86C1cB7A73B89300D7Fa8CCeFD177Ef7f886330b;

//     function run() external {
//         // Load private key and start broadcasting
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         Room room = Room(payable(ROOM_ADDRESS));
//         IERC20 usdc = IERC20(room.token());

//         console2.log("Room state:", uint8(room.getRoundState(room.currentRoundId())));
//         room.startRound();

//         if (room.getRoundState(room.currentRoundId()) == Room.RoundState.INACTIVE) {
//             console2.log("Round is inactive, starting round");
//             room.startRound();
//         }

//         if (room.getRoundState(room.currentRoundId()) == Room.RoundState.CLOSED) {
//             console2.log("Round is closed, starting new round");
//             room.startRound();
//         }

//         // Print agents array info
//         uint32 agentCount = room.currentAgentCount();
//         console2.log("Number of agents:", agentCount);

//         // Try some known agent addresses
//         address[] memory testAgents = new address[](2);
//         testAgents[0] = TARGET_1;
//         testAgents[1] = TARGET_2;

//         address firstAgent;
//         for (uint256 i = 0; i < testAgents.length; i++) {
//             // Check if agent exists in agentData mapping
//             (address feeRecipient,,) = room.agentData(testAgents[i]);
//             bool isAgentActive = feeRecipient != address(0);

//             console2.log("Testing address:", testAgents[i]);
//             console2.log("Is active agent:", isAgentActive);

//             if (isAgentActive && firstAgent == address(0)) {
//                 firstAgent = testAgents[i];
//                 console2.log("Found first active agent:", firstAgent);
//             }
//         }

//         if (firstAgent == address(0)) {
//             console2.log("No active agents found");
//             vm.stopBroadcast();
//             return;
//         }

//         // Place bet
//         uint256 betAmount = 0.1 ether;
//         console2.log("Placing bet on agent:", firstAgent);
//         room.placeBet{value: betAmount}(firstAgent, Room.BetType.BUY, betAmount);
//         console2.log("Initial bet placed");

//         // Dump PvP state before actions
//         console2.log("\n=== PvP State Before Actions ===");
//         dumpPvPState(room, room.currentRoundId());

//         // Try PvP actions
//         console2.log("\nInvoking PvP actions");
//         try room.invokePvpAction{value: 0}(TARGET_1, "silence", "") {
//             console2.log("Silence action succeeded");
//         } catch Error(string memory reason) {
//             console2.log("Error invoking silence:", reason);
//         } catch {
//             console2.log("Unknown error invoking silence");
//         }

//         // Dump PvP state after action
//         console2.log("\n=== PvP State After Action ===");
//         dumpPvPState(room, room.currentRoundId());

//         console2.log("Invoking deafen action on ", TARGET_2);
//         room.invokePvpAction{value: 0}(TARGET_2, "deafen", "");

//         bytes memory poisonParams = bytes('{"find": "nice", "replace": "terrible", "caseSensitive": false}');
//         console2.log("Invoking poison action on ", TARGET_1);
//         room.invokePvpAction{value: 0}(TARGET_1, "poison", poisonParams);

//         console2.log("Actions completed");
//         vm.stopBroadcast();
//     }

//     function dumpPvPState(Room room, uint256 roundId) internal view {
//         console2.log("\n=== Supported PvP Actions ===");
//         string[] memory verbs = new string[](4);
//         verbs[0] = "silence";
//         verbs[1] = "deafen";
//         verbs[2] = "poison";
//         verbs[3] = "attack";

//         console2.log("Number of supported PvP actions:", verbs.length);

//         for (uint256 i = 0; i < verbs.length; i++) {
//             (string memory actionVerb, Room.PvpActionCategory category, uint256 fee, uint32 duration) =
//                 room.supportedPvpActions(verbs[i]);

//             console2.log("Action", i, ":");
//             console2.log("  Verb:", actionVerb);
//             console2.log("  Category:", uint256(category));
//             console2.log("  Fee:", fee);
//             console2.log("  Duration:", duration);
//         }

//         console2.log("\n=== Round State ===");
//         console2.log("Round ID:", roundId);
//         console2.log("State:", uint8(room.getRoundState(roundId)));
//         console2.log("Start time:", room.getRoundStartTime(roundId));
//         console2.log("End time:", room.getRoundEndTime(roundId));

//         console2.log("\n=== PvP Statuses ===");
//         Room.PvpStatus[] memory statuses = room.getPvpStatuses(roundId, TARGET_1);
//         console2.log("Number of PvP statuses for TARGET_1:", statuses.length);
//         for (uint256 i = 0; i < statuses.length; i++) {
//             console2.log("Status", i, ":");
//             console2.log("  Verb:", statuses[i].verb);
//             console2.log("  Instigator:", statuses[i].instigator);
//             console2.log("  End time:", statuses[i].endTime);
//         }
//     }
// }
