//SPDX-License-Identifier : MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "./Core.sol";

contract Room is Ownable, ReentrancyGuard {
    error Room_RoundActive(uint256 roundId);
    error Room_RoundInactive();
    error Room_AlreadyParticipant();
    error Room_NotParticipant();
    error Room_AgentNotActive(address agent);
    error Room_RoundNotActive(uint256 roundId);
    error Room_InvalidAmount();
    error Room_NoWinnings();
    error Room_InvalidBetType();

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
    event FeesDistributed(uint256 indexed roundId, uint256 roomcreatorCut, uint256 daoCut, uint256 agentcreatorCut);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 winnings);

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
        if (rounds[currentRoundId].endTime > block.timestamp) {
            revert Room_RoundActive(currentRoundId);
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
    }

    function joinRoom() public {
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

    function placeBet(address agent, BetType betType, uint256 amount) public {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) {
            revert Room_RoundNotActive(currentRoundId);
        }
        if (!isAgent[agent]) {
            revert Room_AgentNotActive(agent);
        }
        if (amount <= 0) {
            revert Room_InvalidAmount();
        }
        UserBet storage userBet = round.bets[msg.sender];
        AgentPosition storage position = round.agentPositions[agent];
        if (betType == BetType.BUY) {
            position.buyPool += amount;
        } else {
            position.notBuyPool += amount;
        }

        userBet.bettype = betType;
        userBet.amount = amount;

        USDC.transferFrom(msg.sender, address(this), amount);
        emit BetPlaced(msg.sender, currentRoundId, agent, betType, amount);
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
            }
            unchecked {
                ++i;
            }
        }
        return totalWinnings;
    }

    //function to resolve market round
    //function for checkupkeep,performupkeep to change round state
    //function to submit agent decision

    //too much gas, gotta refactor
    /*function _distributeFees(uint256 roundId) internal{
        Round storage round = rounds[roundId];
        uint256 totalFees = round.totalFees;
        uint256 roomCreatorCut = (totalFees * core.fees.roomCreatorCut()) / core.BASIS_POINTS();
        uint256 agentCreatorCut = (totalFees * core.fees.agentCreatorCut()) / core.BASIS_POINTS();
        uint256 daoCut = (totalFees * core.fees.daoCut()) / core.BASIS_POINTS();
    
        USDC.transfer(creator, roomCreatorCut);
        USDC.transfer(core.dao(), daoCut);
        uint256 agentCreatorShare = agentCreatorCut / 5;
        for(uint256 i; i < 5; i++){
            (address agentcreator,) = core.getAgent(round.agent[i]);
            USDC.transfer(agentcreator, agentCreatorShare); //recheck 
        }
        emit FeesDistributed(roundId);

    }*/
}
