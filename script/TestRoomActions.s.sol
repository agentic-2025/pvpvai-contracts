// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Room.sol";
import "../src/interfaces/IPvP.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console2.sol";

contract TestRoomActions is Script {
    // Constants for target addresses
    address constant TARGET_1 = 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d;
    address constant TARGET_2 = 0x830598617569AfD7Ad16343f5D4a226578b16A3d;
    address constant ROOM_ADDRESS = 0xf01B10A7E1855659A00C320ceB82F6A18bA01bf4;

    function run() external {
        // Load private key and start broadcasting
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the room address from environment
        // address roomAddress = vm.envAddress("ROOM_ADDRESS");
        // Room room = Room(roomAddress);
        Room room = Room(ROOM_ADDRESS);
        IERC20 usdc = IERC20(room.USDC());

        // room.performUpKeep("");
        console2.log("Round state:", ROOM_ADDRESS);

        if (room.getRoundState(room.currentRoundId()) == Room.RoundState.INACTIVE) {
            console2.log("Round is inactive, starting round");
            room.startRound();
        }

        if (room.getRoundState(room.currentRoundId()) == Room.RoundState.CLOSED) {
            console2.log("Round is closed, starting new round");
            room.startRound();
        }

        // Print agents array info
        uint32 agentCount = room.currentAgentCount();
        console2.log("Number of agents:", agentCount);

        // Try some known agent addresses
        address[] memory testAgents = new address[](2);
        testAgents[0] = TARGET_1;
        testAgents[1] = TARGET_2;
        // testAgents[2] = 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db; // Add another test address

        address firstAgent;
        for (uint256 i = 0; i < testAgents.length; i++) {
            bool isAgentActive = room.isAgent(testAgents[i]);
            console2.log("Testing address:", testAgents[i]);
            console2.log("Is active agent:", isAgentActive);

            if (isAgentActive && firstAgent == address(0)) {
                firstAgent = testAgents[i];
                console2.log("Found first active agent:", firstAgent);
            }
        }

        if (firstAgent == address(0)) {
            console2.log("No active agents found");
            vm.stopBroadcast();
            return;
        }

        // Rest of the code using firstAgent
        uint256 betAmount = 100 * 10 ** 6; // 100 USDC
        usdc.approve(address(room), betAmount);

        console2.log("Placing bet on agent:", firstAgent);
        room.placeBet(firstAgent, Room.BetType.BUY, betAmount);
        console2.log("Initial bet placed");

        // 3. Update bet
        uint256 newBetAmount = 150 * 10 ** 6; // 150 USDC
        usdc.approve(address(room), newBetAmount - betAmount);
        room.updateBet(firstAgent, Room.BetType.HOLD, newBetAmount);
        console2.log("Bet updated");

        // Add debug logs
        console2.log("Diamond address:", room.diamond());

        // Try to get supported PvP actions first
        try IPvPFacet(room.diamond()).getSupportedPvpActions() returns (IPvP.PvpAction[] memory actions) {
            console2.log("Number of supported PvP actions:", actions.length);
            for (uint256 i = 0; i < actions.length; i++) {
                console2.log("Action verb:", actions[i].verb);
            }
        } catch Error(string memory reason) {
            console2.log("Error getting supported actions:", reason);
        } catch {
            console2.log("Unknown error getting supported actions");
        }

        // log supported actioon on facet
        try IPvPFacet(room.diamond()).getSupportedPvpActionsForRound(room.currentRoundId) returns (IPvP.PvpAction[] memory actions) {
            console2.log("Number of supported PvP actions:", actions.length);
            for (uint256 i = 0; i < actions.length; i++) {
                console2.log("Action verb:", actions[i].verb);
            }
        }
        catch {
            console2.log("Unknown error getting supported actions");
        }
        // Original PvP action calls with try-catch
        console2.log("Invoking PvP actions");
        try room.invokePvpAction(TARGET_1, "silence", "") {
            console2.log("Silence action succeeded");
        } catch Error(string memory reason) {
            console2.log("Error invoking silence:", reason);
        } catch {
            console2.log("Unknown error invoking silence");
        }

        console2.log("Invoking deafen action on ", TARGET_2);
        room.invokePvpAction(TARGET_2, "deafen", "");
        bytes memory poisonParams = bytes('{"find": "nice", "replace": "terrible", "caseSensitive": false}');
        console2.log("Invoking poison action on ", TARGET_1);
        room.invokePvpAction(TARGET_1, "poison", poisonParams);

        console2.log("Actions completed");
        vm.stopBroadcast();
    }
}
