//SPDX-License-Identifier : MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "./Core.sol";
import "./interfaces/IPvP.sol";
import "forge-std/console2.sol";
import "./facets/PvPFacet.sol";

interface IPvPFacet is IPvP {}

contract Room is Ownable, ReentrancyGuard {
    error Room_RoundNotClosed(uint256 currentRoundId);
    error Room_RoundActive(uint256 roundId);
    error Room_RoundInactive(RoundState roundState);
    error Room_AlreadyParticipant();
    error Room_NotParticipant();
    error Room_AgentNotActive(address agent);
    error Room_RoundNotActive(uint256 roundId);
    error Room_InvalidAmount();
    error Room_NoWinnings();
    error Room_InvalidBetType();
    error Room_RoundNotProcessing();
    error Room_NotGameMaster();
    error Room_NotCreator();
    error Room_NotGameMasterOrCreator();
    error Room_MaxAgentsReached();
    error Room_AgentAlreadyExists();
    error Room_InvalidRoundDuration();
    error Room_InvalidPvpAction();
    error Room_InvalidFee();
    error Room_InvalidDuration();
    error Room_InsufficientBalance();
    error Room_TransferFailed();
    error Room_InvalidAgents();
    error Room_NotAuthorized();
    error Room_StatusEffectAlreadyActive(string verb, address target, uint40 endTime);
    error Room__AlreadyInitialized();

    enum BetType {
        BUY,
        HOLD,
        SELL,
        KICK
    }
    enum RoundState {
        INACTIVE,
        ACTIVE,
        PROCESSING,
        CLOSED
    }

    address payable public core;
    IERC20 public USDC;
    RoomFees public fees;
    uint256 public feeBalance;

    address public gameMaster;
    address public token;
    address public creator;
    uint256 public currentRoundId;
    address[] public agents;
    uint32 public maxAgents = 5;
    uint32 public currentAgentCount = 0;
    uint256 public immutable USDC_DECIMALS = 6;
    uint40 public roundDuration = 1 minutes;
    // uint256 public PROCESSING_DURATION = 1 minutes;
    uint256 public PROCESSING_DURATION = 1 seconds; //TODO Just for testing
    bool public pvpEnabled = true;

    struct Round {
        RoundState state;
        uint40 startTime;
        uint40 endTime;
        uint256 totalFees;
        uint256 totalBetsBuy;
        uint256 totalBetsHold;
        uint256 totalBetsSell;
        mapping(address => UserBet) bets;
        mapping(address => AgentPosition) agentPositions;
        mapping(address => bool) hasClaimedWinnings;
    }

    struct RoomFees {
        uint256 roomEntryFee;
    }

    struct UserBet {
        BetType bettype;
        uint256 amount;
        bool refunded;
    }

    struct AgentPosition {
        uint256 buyPool;
        uint256 hold;
        uint256 sell;
        BetType decision;
        bool hasDecided;
    }

    mapping(uint256 => Round) public rounds; //roundid to struct
    mapping(address => bool) public isAgent;
    mapping(address => bool) public roomParticipants;
    // Maps the agent address to the wallet address who should receive the agent's share of the fees. This is only expected to ever be the creator.
    mapping(address => address) agentFeeRecipient;

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
    event FeesUpdated(uint256 roomEntryFee);
    event RoundDurationUpdated(uint40 oldDuration, uint40 newDuration);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);

    modifier onlyGameMaster() {
        if (msg.sender != gameMaster) revert Room_NotGameMaster();
        _;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert Room_NotCreator();
        _;
    }

    modifier onlyGameMasterOrCreator() {
        if (msg.sender != gameMaster && msg.sender != creator) revert Room_NotGameMasterOrCreator();
        _;
    }

    bool private initialized;

    modifier onlyCore() {
        require(msg.sender == core, "Room: caller is not core");
        _;
    }

    address public diamond;

    constructor() Ownable(msg.sender) {
        // No initialization needed here since this is just the implementation
    }

    function initialize(
        address _gameMaster,
        address _token,
        address _creator,
        address _core,
        address _usdc,
        uint256 _roomEntryFee,
        address[] memory _initialAgents,
        address _diamond
    ) external {
        console2.log("Initializing Room");
        if (initialized) {
            console2.log("Room already initialized");
            revert Room__AlreadyInitialized();
        }

        gameMaster = _gameMaster;
        token = _token;
        creator = _creator;
        core = payable(_core);
        USDC = IERC20(_usdc);
        fees = RoomFees({roomEntryFee: _roomEntryFee});
        for (uint256 i; i < _initialAgents.length; i++) {
            isAgent[_initialAgents[i]] = true;
            currentAgentCount++;
        }

        initialized = true;
        diamond = _diamond;

        // Initialize the first round's PvP storage
        Round storage round = rounds[currentRoundId];
        round.state = RoundState.ACTIVE;

        // Initialize PvP Facet's storage for this round
        PvPFacet(diamond).updateRoundState(currentRoundId, uint8(RoundState.ACTIVE));
    }

    // Will worry about colledting the fee for the agent creator later, let's just get something functional for now
    function addAgent(address agent) public onlyGameMasterOrCreator {
        if (currentAgentCount >= maxAgents) revert Room_MaxAgentsReached();
        if (isAgent[agent]) revert Room_AgentAlreadyExists();
        isAgent[agent] = true;
        agents.push(agent);
        currentAgentCount++;
        emit AgentAdded(agent);
    }

    function removeAgent(address agent) public onlyGameMasterOrCreator {
        if (!isAgent[agent]) revert Room_AgentNotActive(agent);
        isAgent[agent] = false;
        currentAgentCount--;
        emit AgentRemoved(agent);
    }

    function updateFees(uint256 roomEntryFee) public onlyCreator {
        fees = RoomFees({roomEntryFee: roomEntryFee});
        emit FeesUpdated(roomEntryFee);
    }

    function updateRoundDuration(uint40 newDuration) public onlyCreator {
        uint40 oldDuration = roundDuration;
        if (newDuration < 10 seconds) revert Room_InvalidRoundDuration(); //Agents have unpredictable arch, need some time for diverse setups
        roundDuration = newDuration;
        emit RoundDurationUpdated(oldDuration, newDuration);
    }

    function joinRoom() public nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) revert Room_RoundInactive(round.state);
        if (roomParticipants[msg.sender]) revert Room_AlreadyParticipant();
        uint256 amount = fees.roomEntryFee;
        USDC.transferFrom(msg.sender, address(this), amount);
        roomParticipants[msg.sender] = true;
        round.totalFees += amount;
        emit JoinedRoom(msg.sender, currentRoundId);
    }

    function placeBet(address agent, BetType betType, uint256 amount) public nonReentrant {
        if (betType == BetType.KICK) {
            revert Room_InvalidBetType();
        }

        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) {
            revert Room_RoundInactive(round.state);
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
        } else if (betType == BetType.HOLD) {
            position.hold += amount;
        } else if (betType == BetType.SELL) {
            position.sell += amount;
        }

        userBet.bettype = betType;
        userBet.amount = amount;

        emit BetPlaced(msg.sender, currentRoundId, agent, betType, amount);
    }

    function updateBet(address agent, BetType newBetType, uint256 newAmount) external nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) revert Room_RoundInactive(round.state);
        if (newAmount == 0) revert Room_InvalidAmount();

        UserBet storage userBet = round.bets[msg.sender];
        AgentPosition storage position = round.agentPositions[agent];

        if (userBet.bettype == BetType.BUY) {
            position.buyPool -= userBet.amount;
        } else {
            position.hold -= userBet.amount;
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
    }

    function calculateWinnings(uint256 roundId, address user) public view returns (uint256) {
        Round storage round = rounds[roundId];
        uint256 totalWinnings = 0;

        for (uint256 i; i < maxAgents; i++) {
            address agent = agents[i];
            AgentPosition storage position = round.agentPositions[agent];

            UserBet storage userBet = round.bets[user];

            if (position.hasDecided && userBet.bettype == position.decision) {
                uint256 winningPool;
                uint256 totalPool = position.buyPool + position.hold;

                if (userBet.bettype == BetType.BUY) {
                    winningPool = position.buyPool;
                } else {
                    winningPool = position.hold;
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

    function startRound() public onlyGameMaster {
        if (rounds[currentRoundId].state != RoundState.INACTIVE && rounds[currentRoundId].state != RoundState.CLOSED) {
            revert Room_RoundNotClosed(currentRoundId);
        }

        currentRoundId++;
        Round storage round = rounds[currentRoundId];
        round.startTime = uint40(block.timestamp);
        round.endTime = uint40(block.timestamp + roundDuration);
        round.state = RoundState.ACTIVE;

        // Update PvP Facet's storage
        PvPFacet(diamond).updateRoundState(currentRoundId, uint8(RoundState.ACTIVE));
        PvPFacet(diamond).startRound(currentRoundId);

        emit RoundStarted(currentRoundId, round.startTime, round.endTime);
    }

    function submitAgentDecision(address agent, BetType decision) public {
        // Only game master or agent can call this function
        if (msg.sender != gameMaster && !isAgent[msg.sender]) revert Room_NotAuthorized();

        // Only game master can submit the "KICK" decision
        if (decision == BetType.KICK && msg.sender != gameMaster) revert Room_NotGameMaster();

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
            for (uint256 i; i < maxAgents; i++) {
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
        // Update PvP Facet's storage
        try PvPFacet(diamond).updateRoundState(currentRoundId, uint8(RoundState.CLOSED)) {}
        catch {
            console2.log("Failed to update PvP Facet round state");
        }
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

    function performUpKeep(bytes calldata) external onlyGameMaster {
        Round storage round = rounds[currentRoundId];

        if (round.state == RoundState.ACTIVE && block.timestamp >= round.endTime) {
            round.state = RoundState.PROCESSING;
            // Update PvP Facet's storage
            try PvPFacet(diamond).updateRoundState(currentRoundId, uint8(RoundState.PROCESSING)) {}
            catch {
                console2.log("Failed to update PvP Facet round state");
            }
            emit RoundStateUpdated(currentRoundId, RoundState.PROCESSING);
        } else if (round.state == RoundState.PROCESSING && block.timestamp >= round.endTime + PROCESSING_DURATION) {
            resolveMarket();
        }
    }

    function _distributeFees(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        uint256 totalFees = round.totalFees;

        (,, uint256 roomCreatorPercent, uint256 agentCreatorPercent, uint256 daoPercent) = Core(payable(core)).getFees();

        uint256 basisPoint = Core(payable(core)).BASIS_POINTS();

        uint256 roomCreatorCut = (totalFees * roomCreatorPercent) / basisPoint;
        uint256 agentCreatorCut = (totalFees * agentCreatorPercent) / basisPoint;

        USDC.transfer(creator, roomCreatorCut);

        uint256 agentCreatorShare = agentCreatorCut / 5;

        //TODO Only commented this out to not have to deal with type error
        // for (uint256 i; i < maxAgents; i++) {
        //     (address agentcreator,) = core.getAgent(agents[i]);
        //     USDC.transfer(agentcreator, agentCreatorShare);
        // }
        uint256 totalDistributed = roomCreatorCut + (agentCreatorShare * 5);
        uint256 dust = totalFees - totalDistributed - daoPercent;
        address dao = Core(payable(core)).dao();
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

    // function checkIsAgent(address agent) public view returns (bool) {
    //     return isAgent[agent];
    // }

    function checkRoomParticipant(address participant) public view returns (bool) {
        return roomParticipants[participant];
    }

    function getHasClaimedWinnings(uint256 roundId, address user) public view returns (bool) {
        return rounds[roundId].hasClaimedWinnings[user];
    }

    function invokePvpAction(address target, string memory verb, bytes memory parameters) public {
        console2.log("(Room) Invoking PvP action", verb, "on ", target);
        IPvPFacet(diamond).invokePvpAction(target, verb, parameters);
    }

    function getPvpStatuses(uint256 roundId, address agent) public view returns (IPvP.PvpStatus[] memory) {
        return IPvPFacet(diamond).getPvpStatuses(roundId, agent);
    }
}
