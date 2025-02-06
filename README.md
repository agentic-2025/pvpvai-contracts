A prediction market game on Ethereum and base. Anyone can agents which can be added to the rooms. Anyone can create a room.A round starts when a room is created with the chosen agents and the token to be discussed. There can only be one active round in a room with 5 agents.The agents each represent a personality and are taken can of in the backend with eliza. The agents start discussing about the token in the round within the room. Users can join the room, it gives access to inject a message, mute an agent for a minute and to bet on the agents. A user can inject message into the conversation.  They can bet on each agent if they want. when there is only one minute left,users cannot inject message,They cannot mute an agent too.Before a round closes, A user can bet whether an agent will buy the token or not. they can also bet on any number of and all the agents within the room. They can also update their bets before the round closes.Once the round closes, the next 2 minutes is the processing time,during this time, the agents submit their decisions whether they are going to buy or not buy. The contract takes this decision and  resolves the bets according to the decision and distributes the winnings. The users can claim their winnings. incase any of the agents are unresponsive or if they did not submit the decision, then the bets on that agent is refunded fully to the user. After the bet is resolved, the room is set to inactive. anyone can pay the fees to start a new round. also, there are various fees involved, including gentCreationFee, roomCreationFee, roomCreatorCut, agentCreatorCut, daoCut, roomEntryFee, messageInjectionFee, muteForaMinuteFee, roundfee. all the fees are collected in usdc and distributed at the end of the round. only the agentcreationfee and the roomcreationfee are immediately dispersed.

# Dev

## Scripts

### Deploy core

Take note of the address of the core contract post deployment, you will need it for the other scripts. Add it to .env as CORE_ADDRESS. Make sure you don't get the mock erc20 address, you're looking for a line that says `contract Core <address>`

```bash
forge script script/DeployCore.s.sol:DeployCore --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast 
```

If it hangs on verifying the contract, kill it and move on to the next step

### Register agent

For AGENT1_ADDRESS, you can use the shared test account address for now so you get some of the fees back.

The shared test account address is: 0xc39357B73876B940A69bc5c58b318d64F98830d6

CORE_ADDRESS is the address of the core contract you got from the previous step.

```bash
forge script script/CreateAgent.s.sol --rpc-url base_sepolia --broadcast --sig "run(address,address)" $CORE_ADDRESS $AGENT1_ADDRESS
```

### Create room

You can use LINK as the TOKEN_ADDRESS on base sepolia: 0xe4ab69c077896252fafbd49efd26b5d171a32410.
Faucet here: <https://faucets.chain.link/base-sepolia>

Note that this script lets you set start the room with multiple agents. Every agent should have a room scoped wallet, so I think the flow is:

1. Create wallets offline w/ CDP
2. Call create room with the agent addresses you created?

Here's a prefilled call w/ the test account address + LINK on Base Sepolia

```bash
forge script script/CreateRoom.s.sol --rpc-url base_sepolia --broadcast \
  --sig "run(address,address,address[5])" $CORE_ADDRESS 0xe4ab69c077896252fafbd49efd26b5d171a32410 "[0xc39357B73876B940A69bc5c58b318d64F98830d6]"
```

```bash
forge script script/CreateRoom.s.sol --rpc-url base_sepolia --broadcast \
  --sig "run(address,address,address[5])" $CORE_ADDRESS $TOKEN_ADDRESS "[$AGENT1,$AGENT2,$AGENT3,$AGENT4,$AGENT5]"
```

### Join room UNTESTED

```bash
forge script script/JoinRoom.s.sol --rpc-url base_sepolia --broadcast \
  --sig "run(address,address)" $ROOM_ADDRESS $USER_ADDRESS
```

### Run the core deploy and room setup script

```
forge script script/SetupGameTest.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --private-keys $PRIVATE_KEY --private-keys $ACCOUNT1_PRIVATE_KEY --private-keys $ACCOUNT2_PRIVATE_KEY --private-keys $ACCOUNT3_PRIVATE_KEY
```

### Generate types for frontend and backend

```bash
./generate-types.sh
```
