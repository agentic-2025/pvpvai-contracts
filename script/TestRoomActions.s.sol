// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Room.sol";
import "../src/interfaces/IPvP.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestRoomActions is Script {
    // Constants for target addresses
    address constant TARGET_1 = 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d;
    address constant TARGET_2 = 0x830598617569AfD7Ad16343f5D4a226578b16A3d;

    function run() external {
        // Load private key and start broadcasting
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the room address from environment
        address roomAddress = vm.envAddress("ROOM_ADDRESS");
        Room room = Room(roomAddress);
        IERC20 usdc = IERC20(room.USDC());

        // Print agents array info
        uint32 agentCount = room.currentAgentCount();
        console.log("Number of agents:", agentCount);
        
        for(uint32 i = 0; i < agentCount; i++) {
            try room.agents(i) returns (address agent) {
                console.log("Agent", i, ":", agent);
            } catch {
                console.log("Failed to get agent at index", i);
            }
        }

        // 2. Place initial bet
        // First approve USDC spending
        uint256 betAmount = 100 * 10 ** 6; // 100 USDC
        usdc.approve(address(room), betAmount);

        console.log("Placing initial bet", betAmount, address(room));
        // Place bet on the first agent
        console.log("Placing bet on agent");
        address agent = room.agents(0);
        console.log("Placing bet on agent", agent);
        room.placeBet(agent, Room.BetType.BUY, betAmount);
        console.log("Initial bet placed");

        // 3. Update bet
        uint256 newBetAmount = 150 * 10 ** 6; // 150 USDC
        usdc.approve(address(room), newBetAmount - betAmount); // Approve additional amount
        room.updateBet(agent, Room.BetType.HOLD, newBetAmount);
        console.log("Bet updated");

        // 4. Invoke PvP actions
        // Silence action - empty parameters
        room.invokePvpAction(TARGET_1, "silence", "");
        console.log("Silence action invoked against", TARGET_1);

        // Deafen action - empty parameters
        room.invokePvpAction(TARGET_2, "deafen", "");
        console.log("Deafen action invoked against", TARGET_2);

        // Poison action with parameters
        bytes memory poisonParams = bytes('{"find": "nice", "replace": "terrible", "caseSensitive": false}');
        room.invokePvpAction(TARGET_1, "poison", poisonParams);
        console.log("Poison action invoked against", TARGET_1);

        // // 1. Start a round
        // room.performUpKeep("");

        // //sleep 1s
        // vm.roll(block.number + 1);
        // vm.warp(block.timestamp + 1 seconds);
        // room.performUpKeep("");

        // room.startRound();

        console.log("Round started");
        vm.stopBroadcast();
    }
}
