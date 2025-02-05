//SPDX-License-Identifier : MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "./Core.sol";

contract Room is Ownable, ReentrancyGuard {
    error Room_RoundNotClosed(uint256 currentRoundId);
    error Room_RoundActive(uint256 roundId);
    error Room_RoundInactive();
    error Room_AlreadyParticipant();
    error Room_NotParticipant();
    error Room_AgentNotActive(address agent);
    error Room_RoundNotActive(uint256 roundId);
    error Room_InvalidAmount();
    error Room_NoWinnings();
    error Room_InvalidBetType();
    error Room_RoundNotProcessing();

    enum BetType {
        NONE,
        BUY,
        NOT_BUY
    }
    enum RoundState {
        INACTIVE,
        ACTIVE,
        PROCESSING,
        CLOSED
    }

    Core public immutable core;
    IERC20 public immutable USDC;
    RoomFees public fees;

    address public token;
    address public creator;
    uint256 public currentRoundId;
    address[5] public agents;
    uint256 public immutable USDC_DECIMALS = 6;
    uint256 public PROCESSING_DURATION = 1 minutes;

    struct Round {
        RoundState state;
        uint40 startTime;
        uint40 endTime;
        uint256 totalFees;
        mapping(address => UserBet) bets;
        mapping(address => AgentPosition) agentPositions;
        mapping(address => bool) hasClaimedWinnings;
    }

    struct RoomFees {
        uint256 roomEntryFee;
        uint256 messageInjectionFee;
        uint256 muteForaMinuteFee;
    }

    struct UserBet {
        BetType bettype;
        uint256 amount;
        bool refunded;
    }

    struct AgentPosition {
        uint256 buyPool;
        uint256 notBuyPool;
        BetType decision;
        bool hasDecided;
    }

    mapping(uint256 => Round) public rounds; //roundid to struct
    mapping(address => bool) public isAgent;
    mapping(address => bool) public roomParticipants;
    //mapping(uint256 => mapping(address => bool)) public agentDecisions; //roundid to agentaddress to decision
    //mapping(uint256 => mapping(address => mapping(address => BetType))) public bets; //rounid to useraddress to agentaddress to bet

    event RoundStarted(uint256 indexed roundId, uint40 startTime, uint40 endTime);
    event JoinedRoom(address indexed user, uint256 indexed roundId);
    event MessageInjected(address indexed user, uint256 indexed roundId);
    event MutedForaMinute(address indexed user, uint256 indexed roundId, address indexed agent);
    event BetPlaced(
        address indexed user, uint256 indexed roundId, address indexed agent, BetType betType, uint256 amount
    );
    event FeesDistributed(uint256 indexed roundId);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 winnings);
    event BetUpdated(
        uint256 indexed roundId, address indexed user, address agent, BetType newbetType, uint256 newamount
    );
    event RoundStateUpdated(uint256 indexed currentRoundId, RoundState state);
    event AgentDecisionSubmitted(uint256 indexed roundId, address agent, BetType betType);
    event MarketResolved(uint256 indexed roundId);
    event FeesUpdated(uint256 roomEntryFee, uint256 messageInjectionFee, uint256 muteForaMinuteFee);

    constructor(
        address tokenaddress,
        address creatoraddress,
        address coreaddress,
        address[] memory _agents,
        address usdc,
        uint256 roomEntryFee,
        uint256 messageInjectionFee,
        uint256 muteForaMinuteFee
    ) Ownable(coreaddress) {
        token = tokenaddress;
        creator = creatoraddress;
        USDC = IERC20(usdc);
        core = Core(payable(coreaddress));
        fees = RoomFees({
            roomEntryFee: roomEntryFee,
            messageInjectionFee: messageInjectionFee,
            muteForaMinuteFee: muteForaMinuteFee
        });
        unchecked {
            for (uint256 i; i < _agents.length;) {
                address agent = _agents[i];
                require(!isAgent[agent], "Duplicate agent");
                agents[i] = agent;
                isAgent[agent] = true;
                ++i;
            }
        }
        startRound();
    }

    function startRound() public {
        if (rounds[currentRoundId].state != RoundState.CLOSED) {
            revert Room_RoundNotClosed(currentRoundId);
        }
        currentRoundId++;
        /* rounds[currentRoundId] = Round({
            state: RoundState.ACTIVE,
            startTime: uint40(block.timestamp),
            endTime: uint40(block.timestamp + 5 minutes)
        }); */
        Round storage round = rounds[currentRoundId];
        round.startTime = uint40(block.timestamp);
        round.endTime = uint40(block.timestamp + 30 seconds); //TODO change me later, just tweaked for testing
        // round.endTime = uint40(block.timestamp + 5 minutes);
        round.state = RoundState.ACTIVE;
        emit RoundStarted(currentRoundId, round.startTime, round.endTime);
    }

    function updateFees(uint256 roomEntryFee, uint256 messageInjectionFee, uint256 muteForaMinuteFee) public {
        fees = RoomFees({
            roomEntryFee: roomEntryFee,
            messageInjectionFee: messageInjectionFee,
            muteForaMinuteFee: muteForaMinuteFee
        });
        emit FeesUpdated(roomEntryFee, messageInjectionFee, muteForaMinuteFee);
    }

    function joinRoom() public nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) revert Room_RoundInactive();
        if (roomParticipants[msg.sender]) revert Room_AlreadyParticipant();
        uint256 amount = fees.roomEntryFee;
        USDC.transferFrom(msg.sender, address(this), amount);
        roomParticipants[msg.sender] = true;
        round.totalFees += amount;
        emit JoinedRoom(msg.sender, currentRoundId);
    }

    function injectMessage() public nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) revert Room_RoundInactive();
        if (!roomParticipants[msg.sender]) revert Room_NotParticipant(); //change to modifier

        uint256 amount = fees.messageInjectionFee;
        require(USDC.transferFrom(msg.sender, address(this), amount));
        round.totalFees += amount;
        emit MessageInjected(msg.sender, currentRoundId);
    }

    function muteForaMinute(address agentToMute) public nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.state == RoundState.ACTIVE) revert Room_RoundInactive();
        if (!roomParticipants[msg.sender]) revert Room_NotParticipant();
        if (!isAgent[agentToMute]) revert Room_AgentNotActive(agentToMute);
        uint256 amount = fees.muteForaMinuteFee;
        USDC.transferFrom(msg.sender, address(this), amount);
        emit MutedForaMinute(msg.sender, currentRoundId, agentToMute);
    }

    function placeBet(address agent, BetType betType, uint256 amount) public nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) {
            revert Room_RoundInactive();
        }
        if (!isAgent[agent]) {
            revert Room_AgentNotActive(agent);
        }
        if (amount <= 0) {
            revert Room_InvalidAmount();
        }
        UserBet storage userBet = round.bets[msg.sender];
        AgentPosition storage position = round.agentPositions[agent];

        USDC.transferFrom(msg.sender, address(this), amount);
        if (betType == BetType.BUY) {
            position.buyPool += amount;
        } else {
            position.notBuyPool += amount;
        }

        userBet.bettype = betType;
        userBet.amount = amount;

        emit BetPlaced(msg.sender, currentRoundId, agent, betType, amount);
    }

    function updateBet(address agent, BetType newBetType, uint256 newAmount) external nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) revert Room_RoundInactive();
        if (newAmount == 0) revert Room_InvalidAmount();

        UserBet storage userBet = round.bets[msg.sender];
        AgentPosition storage position = round.agentPositions[agent];

        if (userBet.bettype == BetType.BUY) {
            position.buyPool -= userBet.amount;
        } else {
            position.notBuyPool -= userBet.amount;
        }

        if (newAmount > userBet.amount) {
            uint256 additionalAmount = newAmount - userBet.amount;
            USDC.transferFrom(msg.sender, address(this), additionalAmount);
        } else if (newAmount < userBet.amount - newAmount) {
            uint256 refundAmount = userBet.amount - newAmount;
            USDC.transfer(msg.sender, refundAmount);
        }
        userBet.bettype = newBetType;
        userBet.amount = newAmount;
        emit BetUpdated(currentRoundId, msg.sender, agent, newBetType, newAmount);
    }

    function claimWinnings(uint256 roundId) public nonReentrant {
        Round storage round = rounds[roundId];
        if (round.state != RoundState.CLOSED) revert Room_RoundNotActive(roundId);
        if (!roomParticipants[msg.sender]) revert Room_NotParticipant();
        if (round.hasClaimedWinnings[msg.sender]) revert Room_AlreadyParticipant();
        uint256 winnings = calculateWinnings(roundId, msg.sender);
        if (winnings == 0) revert Room_NoWinnings();

        round.hasClaimedWinnings[msg.sender] = true;
        USDC.transfer(msg.sender, winnings);
        emit WinningsClaimed(roundId, msg.sender, winnings);
        //uint256 winnings = calculateWinnings(roundId, msg.sender);
        //USDC.transfer(msg.sender, winnings);
    }

    function calculateWinnings(uint256 roundId, address user) public view returns (uint256) {
        Round storage round = rounds[roundId];
        uint256 totalWinnings = 0;

        for (uint256 i; i < 5; i++) {
            address agent = agents[i];
            AgentPosition storage position = round.agentPositions[agent];

            UserBet storage userBet = round.bets[user];

            if (position.hasDecided && userBet.bettype == position.decision) {
                uint256 winningPool;
                uint256 totalPool = position.buyPool + position.notBuyPool;

                if (userBet.bettype == BetType.BUY) {
                    winningPool = position.buyPool;
                } else {
                    winningPool = position.notBuyPool;
                }
                if (winningPool > 0) {
                    totalWinnings += (userBet.amount * totalPool) / winningPool;
                }
            } else {
                totalWinnings += userBet.amount;
            }
            unchecked {
                ++i;
            }
        }
        return totalWinnings;
    }
    //gamemaster or the agents can call

    function submitAgentDecision(address agent, BetType decision) public {
        if (!isAgent[agent]) revert Room_AgentNotActive(agent);
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.PROCESSING) revert Room_RoundNotProcessing();
        AgentPosition storage position = round.agentPositions[agent];
        if (position.hasDecided) revert Room_AlreadyParticipant();
        position.decision = decision;
        position.hasDecided = true;
        emit AgentDecisionSubmitted(currentRoundId, agent, decision);
    }

    function refundBets(uint256 roundId, address agent) internal {
        Round storage round = rounds[roundId];
        AgentPosition storage position = round.agentPositions[agent];
        if (!position.hasDecided) {
            for (uint256 i; i < 5; i++) {
                address user = agents[i];
                UserBet storage userBet = round.bets[user];
                if (userBet.bettype == BetType.BUY) {
                    USDC.transfer(user, userBet.amount);
                } else {
                    USDC.transfer(user, userBet.amount);
                }
            }
        }
    }

    function resolveMarket() public {
        Round storage round = rounds[currentRoundId];
        _distributeFees(currentRoundId);
        round.state = RoundState.CLOSED;
        emit MarketResolved(currentRoundId);
    }

    function checkUpKeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory) {
        //ask team if frontend can. chainlink means, creating subscription + link for every room contract
        Round storage round = rounds[currentRoundId];
        if (round.state == RoundState.ACTIVE && block.timestamp >= round.endTime) {
            return (true, "");
        }
        if (round.state == RoundState.PROCESSING && block.timestamp >= round.endTime + PROCESSING_DURATION) {
            return (true, "");
        }
        return (false, "");
    }

    function performUpKeep(bytes calldata) external {
        Round storage round = rounds[currentRoundId];

        if (round.state == RoundState.ACTIVE && block.timestamp >= round.endTime) {
            round.state = RoundState.PROCESSING;
            emit RoundStateUpdated(currentRoundId, RoundState.PROCESSING);
        } else if (round.state == RoundState.PROCESSING && block.timestamp >= round.endTime + PROCESSING_DURATION) {
            resolveMarket();
        }
    }

    function _distributeFees(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        uint256 totalFees = round.totalFees;

        (,, uint256 roomCreatorPercent, uint256 agentCreatorPercent, uint256 daoPercent) = core.getFees();

        uint256 basisPoint = core.BASIS_POINTS();

        uint256 roomCreatorCut = (totalFees * roomCreatorPercent) / basisPoint;
        uint256 agentCreatorCut = (totalFees * agentCreatorPercent) / basisPoint;

        USDC.transfer(creator, roomCreatorCut);

        uint256 agentCreatorShare = agentCreatorCut / 5;
        for (uint256 i; i < 5; i++) {
            (address agentcreator,) = core.getAgent(agents[i]);
            USDC.transfer(agentcreator, agentCreatorShare);
        }
        uint256 totalDistributed = roomCreatorCut + (agentCreatorShare * 5);
        uint256 dust = totalFees - totalDistributed - daoPercent;
        address dao = core.dao();
        USDC.transfer(dao, daoPercent + dust);

        emit FeesDistributed(roundId);
    }

    function getRoomFees() public view returns (RoomFees memory) {
        return fees;
    }

    function getRoundState(uint256 roundId) public view returns (RoundState) {
        return rounds[roundId].state;
    }

    function getRoundStartTime(uint256 roundId) public view returns (uint40) {
        return rounds[roundId].startTime;
    }

    function getRoundEndTime(uint256 roundId) public view returns (uint40) {
        return rounds[roundId].endTime;
    }

    function getUserBet(uint256 roundId, address user) public view returns (UserBet memory) {
        return rounds[roundId].bets[user];
    }

    function getAgentPosition(uint256 roundId, address agent) public view returns (AgentPosition memory) {
        return rounds[roundId].agentPositions[agent];
    }

    function checkIsAgent(address agent) public view returns (bool) {
        return isAgent[agent];
    }

    function checkRoomParticipant(address participant) public view returns (bool) {
        return roomParticipants[participant];
    }

    function getHasClaimedWinnings(uint256 roundId, address user) public view returns (bool) {
        return rounds[roundId].hasClaimedWinnings[user];
    }
    //check access controls for fn
    //check team if indexed param for events
    //additional overrides for gamemaster ,more acess controls?
}
