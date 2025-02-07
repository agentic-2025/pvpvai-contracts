// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Core} from "../src/Core.sol";
import {MockUSDC} from "../src/test/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Room} from "../src/Room.sol";

contract EndToEndTest is Script {
    address public deployer;
    Core public core;
    MockUSDC public usdc;
    Room public room;

    // Test accounts
    address public account1;
    address public account2;
    address public account3;
    uint256 public account1Key;
    uint256 public account2Key;
    uint256 public account3Key;

    // Constants for target addresses (will be set during setup)
    address public TARGET_1;
    address public TARGET_2;
    address public TARGET_3;
    
    //token address
    address public token = 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196;


    // Add fee constants
    uint256 constant STATUS_EFFECT_FEE = 0.0002 ether;
    uint256 constant POISON_FEE = 0.001 ether;
    uint256 constant ATTACK_FEE = 0.0001 ether;

    function setUp() public {
        // Add debug logging
        console2.log("Loading private keys from environment...");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        console2.log("Deployer key loaded:", deployerKey != 0);

        deployer = vm.addr(deployerKey);
        console2.log("Deployer address:", deployer);

        // Load accounts from environment with verification
        account1Key = vm.envUint("ACCOUNT1_PRIVATE_KEY");
        account1 = vm.addr(account1Key);
        account2Key = vm.envUint("ACCOUNT2_PRIVATE_KEY");
        account2 = vm.addr(account2Key);
        account3Key = vm.envUint("ACCOUNT3_PRIVATE_KEY");
        account3 = vm.addr(account3Key);

        console2.log("Account keys loaded:");
        console2.log("Account1 key present:", account1Key != 0);
        console2.log("Account2 key present:", account2Key != 0);
        console2.log("Account3 key present:", account3Key != 0);
        

        
        
        
        console2.log("Account1 address:", account1);
console2.log("Account2 address:", account2);
console2.log("Account3 address:", account3);
    }

    function run() public {
        // === SETUP PHASE ===
        console2.log("\n=== Starting Setup Phase ===\n");

       
        // 2. Deploy Core contract
        vm.broadcast(deployer);
        core = new Core(address(usdc)); // Deploy core
        console2.log("Core deployed at:", address(core));

        // Deploy Room implementation
        vm.broadcast(deployer);
        Room roomImplementation = new Room();
        console2.log("Room implementation deployed at:", address(roomImplementation));

        // 3. Get fees and deposit
        (uint256 roomFee, uint256 agentFee,,,) = core.getFees();
        console2.log("Room creation fee:", roomFee);
        console2.log("Agent creation fee:", agentFee);

       


        // 4. Deposit fees for accounts
        vm.startBroadcast(vm.envUint("ACCOUNT1_PRIVATE_KEY"));
        core.deposit{value: agentFee * 2}();
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("ACCOUNT2_PRIVATE_KEY"));
        core.deposit{value: agentFee}();
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("ACCOUNT3_PRIVATE_KEY"));
        core.deposit{value: agentFee}();
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("ACCOUNT1_PRIVATE_KEY"));
        core.deposit{value: roomFee}();
        vm.stopBroadcast();

        // 5. Create agents
        console2.log("balance of deployer:",deployer.balance );
        console2.log("balance of account1 :", account1.balance);
        vm.broadcast(deployer);
        core.createAgent{value: agentFee}(account1, 1);
        vm.broadcast(deployer);
        core.createAgent{value: agentFee}(account2, 2);
        vm.broadcast(deployer);
        core.createAgent{value: agentFee}(account3, 3);

        // Set target addresses for later use
        TARGET_1 = 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d;
        TARGET_2 = 0x830598617569AfD7Ad16343f5D4a226578b16A3d;
        TARGET_3 = 0x1D5EbEABEE35dbBA6Fd2847401F979b3f6249a93;

        // 6. Register agent wallets
        vm.broadcast(deployer);
        core.registerAgentWallet(1, TARGET_1);
        vm.broadcast(deployer);
        core.registerAgentWallet(2, TARGET_2);
        vm.broadcast(deployer);
        core.registerAgentWallet(3, TARGET_3);

        // 7. Create room
        address[] memory agentWallets = new address[](3);
        agentWallets[0] = TARGET_1;
        agentWallets[1] = TARGET_2;
        agentWallets[2] = TARGET_3;

        address[] memory feeRecipients = new address[](3);
        feeRecipients[0] = account1;
        feeRecipients[1] = account2;
        feeRecipients[2] = account3;

        uint256[] memory agentIds = new uint256[](3);
        agentIds[0] = 1;
        agentIds[1] = 2;
        agentIds[2] = 3;


        vm.broadcast(deployer);
        // Create room
        address roomAddress = core.createRoom(
            deployer, account1, address(usdc), agentWallets, feeRecipients, agentIds, address(roomImplementation)
        );

        room = Room(payable(roomAddress));

        console2.log("Room created at:", roomAddress);

        // Initialize PvP actions
        vm.startBroadcast(deployer);

        room.updateSupportedPvpActions("silence", Room.PvpActionCategory.STATUS_EFFECT, STATUS_EFFECT_FEE, 30);
        room.updateSupportedPvpActions("deafen", Room.PvpActionCategory.STATUS_EFFECT, STATUS_EFFECT_FEE, 30);
        room.updateSupportedPvpActions("poison", Room.PvpActionCategory.STATUS_EFFECT, POISON_FEE, 30);
        room.updateSupportedPvpActions("attack", Room.PvpActionCategory.DIRECT_ACTION, ATTACK_FEE, 0);
        vm.stopBroadcast();

        console2.log("Supported PvP actions updated");
        // === TESTING PHASE ===
        console2.log("\n=== Starting Testing Phase ===\n");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        console2.log("Round state:", uint8(room.getRoundState(room.currentRoundId())));

        if (
            room.getRoundState(room.currentRoundId()) == Room.RoundState.INACTIVE
                || room.getRoundState(room.currentRoundId()) == Room.RoundState.CLOSED
        ) {
            console2.log("Round is inactive, starting round");
            room.startRound();
        }

        // Print agents info
        uint32 agentCount = room.currentAgentCount();
        console2.log("Number of agents:", agentCount);

        // Try some known agent addresses
        address[] memory testAgents = new address[](3);
        testAgents[0] = TARGET_1;
        testAgents[1] = TARGET_2;
        testAgents[2] = TARGET_3;

        address firstAgent;
        for (uint256 i = 0; i < testAgents.length; i++) {
            (address feeRecipient,,) = room.agentData(testAgents[i]);
            bool isAgentActive = feeRecipient != address(0);

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
        vm.stopBroadcast();

        // Place bet
        vm.startBroadcast(account1Key);
    uint256 betAmount1 = 0.001 ether;
    room.placeBet{value: betAmount1}(TARGET_1, Room.BetType.BUY, betAmount1);
    console2.log("Account1 placed bet on TARGET_1:", betAmount1);
    vm.stopBroadcast();

    vm.startBroadcast(account2Key);
    uint256 betAmount2 = 0.002 ether;
    room.placeBet{value: betAmount2}(TARGET_2, Room.BetType.BUY, betAmount2);
    console2.log("Account2 placed bet on TARGET_2:", betAmount2);
    vm.stopBroadcast();

    // Modify a bet
    vm.startBroadcast(account1Key);
    try room.placeBet(TARGET_1, Room.BetType.SELL, betAmount1 / 2) {
        console2.log("Account1 modified bet on TARGET_1");
    } catch Error(string memory reason) {
        console2.log("Failed to modify bet:", reason);
    }
    vm.stopBroadcast();

    // Display current bets
    console2.log("\n=== Current Bets ===");
    dumpBetState(room, room.currentRoundId());

   // Fast forward time to end of round
    vm.warp(block.timestamp + 10 seconds);
    console2.log("\n=== Round Duration Complete ===");
    
    // GameMaster changes round state
    vm.startBroadcast(deployerKey);
    room.changeRoundState(Room.RoundState.PROCESSING);
    console2.log("Round state changed to PROCESSING");
    vm.stopBroadcast();

    // Submit agent decisions
    vm.startBroadcast(deployerKey);
    room.submitAgentDecision(TARGET_1, Room.BetType.SELL);
    console2.log("Agent decision submitted for TARGET_1: SELL");

    room.submitAgentDecision(TARGET_2, Room.BetType.BUY);
    console2.log("Agent decision submitted for TARGET_2: BUY");

    room.submitAgentDecision(TARGET_3, Room.BetType.HOLD);
    console2.log("Agent decision submitted for TARGET_3: HOLD");
    vm.stopBroadcast();

    // GameMaster resolves market
    vm.startBroadcast(deployerKey);
    room.resolveMarket();
    console2.log("Market resolved successfully");
    vm.stopBroadcast();

    // Try claiming winnings
    vm.startBroadcast(account1Key);
    try room.claim(room.roundId()) {
        console2.log("Account1 claimed winnings successfully");
    } catch Error(string memory reason) {
        console2.log("Account1 failed to claim:", reason);
    }
    vm.stopBroadcast();

    vm.startBroadcast(account2Key);
    try room.claim(room.roundId()) {
        console2.log("Account2 claimed winnings successfully");
    } catch Error(string memory reason) {
        console2.log("Account2 failed to claim:", reason);
    }
    vm.stopBroadcast();

    // Check final balances
    console2.log("\n=== Final Balances ===");
    console2.log("Account1 balance:", account1.balance);
    console2.log("Account2 balance:", account2.balance);

    // Test PvP actions
    console2.log("\n=== Testing PvP Actions ===\n");
    dumpPvPState(room, room.currentRoundId());

    try room.invokePvpAction{value: STATUS_EFFECT_FEE}(TARGET_1, "silence", "") {
        console2.log("Silence action succeeded");
    } catch Error(string memory reason) {
        console2.log("Error invoking silence:", reason);
    }

    dumpPvPState(room, room.currentRoundId());

    room.invokePvpAction{value: STATUS_EFFECT_FEE}(TARGET_2, "deafen", "");
    bytes memory poisonParams = bytes('{"find": "nice", "replace": "terrible", "caseSensitive": false}');
    room.invokePvpAction{value: POISON_FEE}(TARGET_1, "poison", poisonParams);

    console2.log("pvp actions test complete");
    vm.stopBroadcast();
    }

    function dumpPvPState(Room _room, uint256 roundId) internal view {
        console2.log("\n=== Supported PvP Actions ===");
        string[] memory verbs = new string[](4);
        verbs[0] = "silence";
        verbs[1] = "deafen";
        verbs[2] = "poison";
        verbs[3] = "attack";

        console2.log("Number of supported PvP actions:", verbs.length);

        for (uint256 i = 0; i < verbs.length; i++) {
            (string memory actionVerb, Room.PvpActionCategory category, uint256 fee, uint32 duration) =
                _room.supportedPvpActions(verbs[i]);

            console2.log("Action", i, ":");
            console2.log("  Verb:", actionVerb);
            console2.log("  Category:", uint256(category));
            console2.log("  Fee:", fee);
            console2.log("  Duration:", duration);
        }

        console2.log("\n=== Round State ===");
        console2.log("Round ID:", roundId);
        console2.log("State:", uint8(_room.getRoundState(roundId)));
        console2.log("Start time:", _room.getRoundStartTime(roundId));
        console2.log("End time:", _room.getRoundEndTime(roundId));

        console2.log("\n=== PvP Statuses ===");

        // Check statuses for all targets
        address[3] memory targets = [TARGET_1, TARGET_2, TARGET_3];
        string[3] memory targetNames = ["TARGET_1", "TARGET_2", "TARGET_3"];

        for (uint256 t = 0; t < targets.length; t++) {
            Room.PvpStatus[] memory statuses = _room.getPvpStatuses(roundId, targets[t]);
            console2.log("\nNumber of PvP statuses for", targetNames[t], ":", statuses.length);
            for (uint256 i = 0; i < statuses.length; i++) {
                console2.log("Status", i, ":");
                console2.log("  Verb:", statuses[i].verb);
                console2.log("  Instigator:", statuses[i].instigator);
                console2.log("  End time:", statuses[i].endTime);
            }
        }
    }
    function dumpBetState(Room _room, uint256 roundId) internal view {
    address[3] memory targets = [TARGET_1, TARGET_2, TARGET_3];
    string[3] memory targetNames = ["TARGET_1", "TARGET_2", "TARGET_3"];

    for (uint256 t = 0; t < targets.length; t++) {
        console2.log("\nBets for", targetNames[t]);
        
        // Get total bets
        (uint256 buyAmount, uint256 sellAmount, uint256 holdAmount) = _room.getTotalBets(roundId, targets[t]);
        console2.log("Total Buy Amount:", buyAmount);
        console2.log("Total Sell Amount:", sellAmount);

        // Try to get specific account bets
        //(uint256 account1Buy, uint256 account1Sell) = _room.getUserBet( targets[t], account1);
        //(uint256 account2Buy, uint256 account2Sell) = _room.getUserBet( targets[t], account2);
        
        //console2.log("Account1 Bets - Buy:", account1Buy, "Sell:", account1Sell);
        //console2.log("Account2 Bets - Buy:", account2Buy, "Sell:", account2Sell);
    }
}
}
