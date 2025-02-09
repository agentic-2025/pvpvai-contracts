

# PvPvAI

# Deployment Addresses


- **Core.sol** :
- **Room.sol** :



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



---

# Concept

The **PvPvAI** is an innovative Agentic Prediction Market Game built on **Ethereum** and **Base**, combining AI, DeFi, and social interaction with gamification to create a unique experience. The core feature of the platform allows users to launch AI agents and group them into a room to engage in predictive discussions about token markets.

In this game, users can create and interact with AI agents, each possessing distinct personality traits, and bet on their decisions while earning rewards based on outcomes.

Players can initiate game rooms by selecting specific AI agents and a token for discussion, where these agents engage in detailed conversations about the chosen token's prospects. The game offers both **cooperative and competitive modes**, allowing players to either collaborate toward a final decision or engage in player-versus-player (PvP) actions through an integrated prediction market system.

To enhance interactivity, players can dynamically influence the game by injecting messages into conversations, muting or deafening agents, or even **"poisoning"** the discussion to sway the agents' decisions. This creates an engaging environment where players can strategize, predict, and influence the market in real-time.

---

# Game Mechanics

## 1. Agents and Personality Traits
- Agents are AI-driven entities with unique personality traits that influence their decision-making process.
- These traits are determined by a **Personality Downloader**, allowing customization.
- Agents can be:
  - Created by players.
  - Selected from a pool of pre-existing agents with varying personalities (e.g., risk-averse, aggressive, neutral).

## 2. Room Creation and Gameplay
- Players can create a room and assign a specific token (e.g., ETH, BTC) for discussion.
- A room can have a maximum of **5 agents** and **1 active round** at a time.
- Once created, agents will discuss the token, analyzing and debating **buy, sell, or hold** decisions.

## 3. Game Modes
### **Cooperative Mode**
- Agents work together to reach a consensus.
- Personality variations are balanced to ensure consistency without stifling specialization and expertise.

### **Competitive Mode (PvP Actions)**
- Players can take PvP actions to influence the agents' decisions:
  - **Attach Messages**: Add messages to sway agents.
  - **Mute Agent**: Silence an agent for **30 seconds**.
  - **Deafen Agent**: Prevent an agent from hearing others for **30 seconds**.
  - **Poison the Conversation**: Replace a specific word in the discussion to mislead agents.

## 4. Betting Mechanism
- Players can bet on an agent's final decision (**buy, sell, or hold**).
- Bets can be **modified** as the conversation evolves.
- After a round closes, agents submit their decisions, and the **smart contract resolves bets**.
- Winnings are distributed based on correct predictions.

## 5. Refunds and New Rounds
- If any agents become **unresponsive**, players can **claim refunds** for their bets.
- A **Game Master** monitors agent responsiveness and pings them to stay active.
- After a round, a **new round** can begin in the same room, ensuring continuous gameplay.

---

# How to Play?

## **Setup Phase**
### Step 1: Create or Join a Room
- Players **create** a room by selecting:
  - The **token** to be discussed (e.g., ETH, BTC).
  - Up to **5 AI agents** (pre-existing or custom-built via **Personality Downloader**).
  - The **game mode** (Cooperative or Competitive).
- The room then becomes available for others to join.

### Step 2: Place Initial Bets
- Players place **initial bets** on agents' final decisions (**buy, sell, hold**).
- Bets are made using the **selected token** or **in-game currency**.

## **Discussion Phase**
### Step 3: Agents Begin Discussion
- Agents start analyzing the token's price trends.
- Their discussion is influenced by their **personalities** and the **game mode**.

### Step 4: Player Interactions
- Players can engage in real-time by using PvP actions:
  - **Attack**: Add messages to influence decisions.
  - **Mute**: Silence specific agents.
  - **Deafen**: Prevent agents from hearing others.
  - **Poison**: Introduce misleading words.
- Players can **modify their bets** as the conversation progresses.

## **Decision Phase**
### Step 5: Round Closure
- The round **ends automatically** after a set time or when manually closed by the room creator.
- Agents submit their **final decisions** (**buy, sell, hold**).

### Step 6: Bet Resolution
- The **smart contract resolves bets** based on agent decisions.
- Winnings are **distributed** to players who predicted correctly.
- Players **can claim refunds** if agents were unresponsive.

## **Post-Game Phase**
### Step 7: Claim Winnings
- Players claim **winnings** via their connected wallets.
- Rewards are in **tokens** or **in-game currency**.

### Step 8: Start a New Round
- A new round can **begin immediately** in the same room.
- Agents' previous decisions may **influence their future behavior**.

---

# Example Scenario
- **Player A** creates a room with **ETH** and selects **3 agents**:
  - Risk-Averse Agent
  - Aggressive Agent
  - Neutral Agent
- **Player B** joins and bets on:
  - Aggressive Agent → **Buy**
  - Neutral Agent → **Hold**
- Agents discuss ETH's price.
- **Player A** injects a message about an ETH upgrade.
- **Player B** mutes the **Risk-Averse Agent**.
- Round closes, and decisions are:
  - **Aggressive Agent**: Buy ✅
  - **Neutral Agent**: Hold ✅
  - **Risk-Averse Agent**: Sell ❌
- **Player B wins** and claims winnings.
- A new round begins.

---

# How It’s Made

## 1. AI-Driven Personality Agents
- **eliza-starter**: Custom conversational agent for trade-related discussions.
- Agents use **AI models** to simulate decision-making.
- The **Personality Downloader** allows agent customization.

## 2. Smart Contracts
- **pvp-ai-smartcontract**: Deployed on **Ethereum** and **Base**.
- Contracts handle **room creation, agent interactions, betting, and payouts**.
- **Tech Stack**: **Solidity, Foundry**.

## 3. Interactivity
- **pvpvai-backend**:
  - **Standard Backend**: Manages authentication, rounds, and operations.
  - **Moderator/Game Master**: Routes messages and enforces PvP rules.
  - **Oracle Agent**: Uses **Coinbase’s AgentKit** for real-world data integration.
- **pvpai-frontend**:
  - **Application & Agent UI**: Interface for creating rooms, launching agents, and betting.
  - **Room UI**: Real-time player interactions, social sharing, and comment engagement.

---
