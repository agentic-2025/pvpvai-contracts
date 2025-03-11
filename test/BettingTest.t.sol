// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "forge-std/console2.sol";
// import "../src/Room.sol";
// import "../src/Core.sol";

// contract BettingTest is Test {
//     Core public core;
//     Room public room;
//     address public gameMaster;
//     address public token;
//     address public creator;
//     address public deployer;
//     address public account1;
//     address public account2;
//     address public account3;
//     address public account4;
//     address public account5;
//     address[] public agents;
//     address[] public agentFeeRecipients;
//     uint256[] public agentIds;

//     // Setup initial values
//     uint256 constant ROOM_CREATION_FEE = 1000000000000000; // 0.001 ETH
//     uint256 constant AGENT_CREATION_FEE = 2000000000000000; // 0.002 ETH
//     uint256 constant BET_AMOUNT_1 = 1000000000000000; // 0.001 ETH
//     uint256 constant BET_AMOUNT_2 = 2000000000000000; // 0.002 ETH
//     uint256 constant PLATFORM_FEE = 250; // 2.5%
//     uint256 constant AGENT_FEE = 250; // 2.5%

//     function setUp() public {
//         // Setup accounts
//         deployer = makeAddr("deployer");
//         gameMaster = makeAddr("gameMaster");
//         creator = makeAddr("creator");
//         token = makeAddr("token");
//         account1 = makeAddr("account1");
//         account2 = makeAddr("account2");
//         account3 = makeAddr("account3");
//         account4 = makeAddr("account4");
//         account5 = makeAddr("account5");

//         // Fund accounts
//         vm.deal(deployer, 100 ether);
//         vm.deal(account1, 10 ether);
//         vm.deal(account2, 10 ether);
//         vm.deal(account3, 10 ether);
//         vm.deal(account4, 10 ether);
//         vm.deal(account5, 10 ether);

//         // Deploy Core contract
//         vm.startPrank(deployer);
//         core = new Core(0xdea3e601C1df6B787E5E3e5aB516495f0e6b4402); //random

//         // Setup initial agents
//         agents = new address[](3);
//         agents[0] = makeAddr("agent1");
//         agents[1] = makeAddr("agent2");
//         agents[2] = makeAddr("agent3");

//         agentFeeRecipients = new address[](3);
//         agentFeeRecipients[0] = makeAddr("feeRecipient1");
//         agentFeeRecipients[1] = makeAddr("feeRecipient2");
//         agentFeeRecipients[2] = makeAddr("feeRecipient3");

//         agentIds = new uint256[](3);
//         agentIds[0] = 1;
//         agentIds[1] = 2;
//         agentIds[2] = 3;

//         // Deploy Room
//         room = new Room();
//         room.initialize(gameMaster, token, creator, address(core), agents, agentFeeRecipients, agentIds);
//         vm.stopPrank();
//     }

//     function testPlaceBet() public {
//         vm.startPrank(gameMaster);
//         room.startRound(); // Don't capture return value
//         uint256 currentRound = room.currentRoundId(); // Get current round from getter
//         room.setCurrentRoundState(Room.RoundState.ACTIVE);
//         vm.stopPrank();

//         uint256 initialBalance = account1.balance;

//         vm.startPrank(account1);
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);

//         Room.UserBet memory bet = room.getUserBet(currentRound, account1);
//         assertEq(bet.amount, BET_AMOUNT_1);
//         assertEq(uint256(bet.bettype), uint256(Room.BetType.BUY));
//         assertEq(account1.balance, initialBalance - BET_AMOUNT_1);

//         // Verify agent position
//         (uint256 buyPool, uint256 sellPool, uint256 holdPool) = room.getTotalBets(currentRound, agents[0]);
//         assertEq(buyPool, BET_AMOUNT_1);
//         assertEq(sellPool, 0);
//         assertEq(holdPool, 0);
//         vm.stopPrank();
//     }

//     function testUpdateBet() public {
//         vm.startPrank(gameMaster);
//         uint256 currentRound = room.currentRoundId();
//         room.setCurrentRoundState(Room.RoundState.ACTIVE);
//         vm.stopPrank();

//         // Place initial bet
//         vm.startPrank(account1);
//         uint256 initialBalance = account1.balance;
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);

//         // Update bet to half amount
//         uint256 newAmount = BET_AMOUNT_1 / 2;
//         room.placeBet{value: 0}(agents[0], Room.BetType.SELL, newAmount);

//         Room.UserBet memory updatedBet = room.getUserBet(currentRound, account1);
//         assertEq(uint256(updatedBet.bettype), uint256(Room.BetType.SELL));
//         assertEq(updatedBet.amount, newAmount);

//         // Check if refund was processed
//         uint256 expectedRefund = BET_AMOUNT_1 - newAmount;
//         assertTrue(
//             account1.balance >= initialBalance - BET_AMOUNT_1 + expectedRefund - 0.01 ether,
//             "Balance after update should be close to expected"
//         );
//         vm.stopPrank();
//     }

//     function testCalculateWinnings() public {
//         vm.startPrank(gameMaster);
//         uint256 currentRound = room.currentRoundId();
//         room.setCurrentRoundState(Room.RoundState.ACTIVE);
//         vm.stopPrank();

//         // Place bets from different accounts on SAME agent
//         vm.startPrank(account1);
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//         vm.stopPrank();

//         vm.startPrank(account2);
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.SELL, BET_AMOUNT_1); // Same amount, opposite bet
//         vm.stopPrank();

//         // Close round and set winner
//         vm.startPrank(gameMaster);
//         room.setCurrentRoundState(Room.RoundState.PROCESSING);
//         room.submitAgentDecision(agents[0], Room.BetType.BUY); // BUY wins, SELL loses
//         room.setCurrentRoundState(Room.RoundState.CLOSED);
//         room.resolveMarket();
//         vm.stopPrank();

//         // Verify winnings for winner (account1)
//         uint256 initialBalance = account1.balance;
//         vm.startPrank(account1);
//         room.claimWinnings(currentRound);
//         assertGt(account1.balance, initialBalance); // Should have received winnings
//         vm.stopPrank();
//     }

//     function testResolveMarket() public {
//         vm.startPrank(gameMaster);
//         room.startRound(); // Don't capture return value
//         uint256 currentRound = room.currentRoundId(); // Get current round from getter
//         room.setCurrentRoundState(Room.RoundState.ACTIVE);
//         vm.stopPrank();

//         // Place multiple bets
//         vm.startPrank(account1);
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//         vm.stopPrank();

//         vm.startPrank(account2);
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.SELL, BET_AMOUNT_1); // Use same amount
//         vm.stopPrank();

//         // Process and resolve market
//         vm.startPrank(gameMaster);
//         room.setCurrentRoundState(Room.RoundState.PROCESSING);

//         // Submit decisions for both agents
//         room.submitAgentDecision(agents[0], Room.BetType.BUY);
//         room.submitAgentDecision(agents[1], Room.BetType.SELL);

//         room.setCurrentRoundState(Room.RoundState.CLOSED);
//         room.resolveMarket();

//         // Verify round is properly closed
//         assertEq(uint256(room.getRoundState(currentRound)), uint256(Room.RoundState.CLOSED));

//         // Verify winners can claim
//         vm.startPrank(account1);
//         room.claimWinnings(currentRound); // Will revert if not a winner
//         vm.stopPrank();
//     }

//     function testMultipleRounds() public {
//         // Test multiple rounds of betting
//         for (uint256 i = 0; i < 3; i++) {
//             vm.startPrank(gameMaster);
//             room.startRound(); // Don't capture return value
//             uint256 currentRound = room.currentRoundId(); // Get current round from getter
//             room.setCurrentRoundState(Room.RoundState.ACTIVE);
//             vm.stopPrank();

//             // Place bets
//             vm.startPrank(account1);
//             room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//             vm.stopPrank();

//             vm.startPrank(account2);
//             room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.SELL, BET_AMOUNT_1);
//             vm.stopPrank();

//             // Close round
//             vm.startPrank(gameMaster);
//             room.setCurrentRoundState(Room.RoundState.PROCESSING);
//             room.submitAgentDecision(agents[0], Room.BetType.BUY);
//             room.setCurrentRoundState(Room.RoundState.CLOSED);
//             room.resolveMarket();
//             vm.stopPrank();

//             // Claim winnings
//             vm.startPrank(account1);
//             room.claimWinnings(currentRound);
//             vm.stopPrank();
//         }
//     }

//     function testEdgeCases() public {
//         vm.startPrank(gameMaster);
//         room.startRound(); // Don't capture return value
//         uint256 currentRound = room.currentRoundId(); // Get current round from getter
//         room.setCurrentRoundState(Room.RoundState.ACTIVE);
//         vm.stopPrank();

//         // Test zero amount bet
//         vm.startPrank(account1);
//         vm.expectRevert(Room.Room_InvalidAmount.selector);
//         room.placeBet{value: 0}(agents[0], Room.BetType.BUY, 0);
//         vm.stopPrank();

//         // Test bet amount mismatch
//         vm.startPrank(account1);
//         vm.expectRevert(Room.Room_InvalidAmount.selector);
//         room.placeBet{value: BET_AMOUNT_2}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//         vm.stopPrank();

//         // Test betting after round is closed
//         vm.startPrank(gameMaster);
//         room.setCurrentRoundState(Room.RoundState.CLOSED);
//         vm.stopPrank();

//         vm.startPrank(account1);
//         vm.expectRevert(
//             abi.encodeWithSelector(
//                 Room.Room_RoundNotExpectedStatus.selector, Room.RoundState.ACTIVE, Room.RoundState.CLOSED
//             )
//         );
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//         vm.stopPrank();
//     }

//     function testMultipleBetsOnAgent() public {
//         vm.startPrank(gameMaster);
//         room.startRound();
//         uint256 currentRound = room.currentRoundId();
//         room.setCurrentRoundState(Room.RoundState.ACTIVE);
//         vm.stopPrank();

//         // Multiple accounts betting BUY
//         vm.startPrank(account1);
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//         vm.stopPrank();

//         vm.startPrank(account2);
//         room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//         vm.stopPrank();

//         // Multiple accounts betting SELL
//         vm.startPrank(account3);
//         room.placeBet{value: BET_AMOUNT_2}(agents[0], Room.BetType.SELL, BET_AMOUNT_2);
//         vm.stopPrank();

//         vm.startPrank(account4);
//         room.placeBet{value: BET_AMOUNT_2}(agents[0], Room.BetType.SELL, BET_AMOUNT_2);
//         vm.stopPrank();

//         // Verify total bets
//         (uint256 buyPool, uint256 sellPool, uint256 holdPool) = room.getTotalBets(currentRound, agents[0]);
//         assertEq(buyPool, BET_AMOUNT_1 * 2);
//         assertEq(sellPool, BET_AMOUNT_2 * 2);
//         assertEq(holdPool, 0);

//         // Close round with BUY winning
//         vm.startPrank(gameMaster);
//         room.setCurrentRoundState(Room.RoundState.PROCESSING);
//         room.submitAgentDecision(agents[0], Room.BetType.BUY);
//         room.setCurrentRoundState(Room.RoundState.CLOSED);
//         room.resolveMarket();
//         vm.stopPrank();

//         // Both BUY bettors should be able to claim
//         uint256 initialBalance1 = account1.balance;
//         uint256 initialBalance2 = account2.balance;

//         vm.startPrank(account1);
//         room.claimWinnings(currentRound);
//         assertGt(account1.balance, initialBalance1);
//         vm.stopPrank();

//         vm.startPrank(account2);
//         room.claimWinnings(currentRound);
//         assertGt(account2.balance, initialBalance2);
//         vm.stopPrank();
//     }

//     function testUpdateMultipleBets() public {
//         vm.startPrank(gameMaster);
//         room.startRound();
//         uint256 currentRound = room.currentRoundId();
//         room.setCurrentRoundState(Room.RoundState.ACTIVE);
//         vm.stopPrank();

//         // Multiple accounts place and update bets
//         vm.startPrank(account1);
//         room.placeBet{value: BET_AMOUNT_2}(agents[0], Room.BetType.BUY, BET_AMOUNT_2);
//         vm.stopPrank();

//         vm.startPrank(account2);
//         room.placeBet{value: BET_AMOUNT_2}(agents[0], Room.BetType.BUY, BET_AMOUNT_2);
//         // Update to lower amount
//         room.placeBet{value: 0}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//         vm.stopPrank();

//         // Verify updated bets
//         (uint256 buyPool, uint256 sellPool, uint256 holdPool) = room.getTotalBets(currentRound, agents[0]);
//         assertEq(buyPool, BET_AMOUNT_2 + BET_AMOUNT_1);
//         assertEq(sellPool, 0);
//         assertEq(holdPool, 0);
//     }

//     function testMultipleRoundsMultipleBets() public {
//         for (uint256 i = 0; i < 2; i++) {
//             vm.startPrank(gameMaster);
//             room.startRound();
//             uint256 currentRound = room.currentRoundId();
//             room.setCurrentRoundState(Room.RoundState.ACTIVE);
//             vm.stopPrank();

//             // Multiple bets in each round
//             vm.startPrank(account1);
//             room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//             vm.stopPrank();

//             vm.startPrank(account2);
//             room.placeBet{value: BET_AMOUNT_1}(agents[0], Room.BetType.BUY, BET_AMOUNT_1);
//             vm.stopPrank();

//             vm.startPrank(account3);
//             room.placeBet{value: BET_AMOUNT_2}(agents[0], Room.BetType.SELL, BET_AMOUNT_2);
//             vm.stopPrank();

//             // Close round
//             vm.startPrank(gameMaster);
//             room.setCurrentRoundState(Room.RoundState.PROCESSING);
//             room.submitAgentDecision(agents[0], Room.BetType.BUY);
//             room.setCurrentRoundState(Room.RoundState.CLOSED);
//             room.resolveMarket();
//             vm.stopPrank();

//             // Both winners claim
//             vm.startPrank(account1);
//             room.claimWinnings(currentRound);
//             vm.stopPrank();

//             vm.startPrank(account2);
//             room.claimWinnings(currentRound);
//             vm.stopPrank();
//         }
//     }
// }
