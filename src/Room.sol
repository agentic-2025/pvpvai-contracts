//SPDX-License-Identifier : MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Core.sol";

contract Room is Ownable, ReentrancyGuard {
    error Room_RoundNotClosed(uint256 currentRoundId);
    error Room_SenderAlreadyClaimedWinnings();
    error Room_SenderHasNoBetInRound();
    error Room_AgentNotActive(address agent);
    error Room_InvalidAmount();
    error Room_NoWinnings();
    error Room_InvalidBetType();
    error Room_RoundNotExpectedStatus(RoundState expected, RoundState actual);
    error Room_NotGameMaster();
    error Room_NotCreator();
    error Room_NotGameMasterOrCreator();
    error Room_MaxAgentsReached();
    error Room_AgentAlreadyExists();
    error Room_InvalidRoundDuration();
    error Room_InvalidPvpAction();
    error Room_InvalidFee();
    error Room_TransferFailed();
    error Room_NotAuthorized();
    error Room_StatusEffectAlreadyActive(string verb, address target, uint40 endTime);
    error Room__AlreadyInitialized();
    error Room_ActionNotSupported();
    error Room_AgentAlreadyDecided();
    error Room_AgentNotExists(address agent);

    enum BetType {
        NONE,
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

    enum PvpActionCategory {
        DIRECT_ACTION,
        STATUS_EFFECT,
        BUFF,
        GAME_BREAKER
    }

    struct PvpAction {
        string verb;
        PvpActionCategory category;
        uint256 fee;
        uint32 duration;
    }

    struct PvpStatus {
        string verb;
        address instigator;
        uint40 endTime;
        bytes parameters;
    }

    address payable public core;
    RoomFees public fees;
    uint256 public feeBalance;

    address public gameMaster;
    address public token;
    address public creator;
    uint256 public currentRoundId;
    address[] public activeAgents;

    uint32 public maxAgents = 5;
    uint32 public currentAgentCount = 0;
    // uint40 public roundDuration = 1 minutes;
    uint40 public roundDuration = 10 seconds;
    uint256 public PROCESSING_DURATION = 1 seconds; //TODO Just for testing
    bool public pvpEnabled;

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
        mapping(address => PvpStatus[]) pvpStatuses;
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

    struct RoomAgent {
        address feeRecipient;
        uint256 coreId;
        bool active;
    }

    mapping(uint256 => Round) public rounds; //roundid to struct
    mapping(address => RoomAgent) public agentData;
    mapping(address => address) agentFeeRecipient;
    mapping(string => PvpAction) public supportedPvpActions;
    string[] public supportedPvpVerbs;

    event RoundStarted(uint256 indexed roundId, uint40 startTime, uint40 endTime);
    event JoinedRoom(address indexed user, uint256 indexed roundId);
    event BetPlaced(
        address indexed user, uint256 indexed roundId, address indexed agent, BetType betType, uint256 amount
    );
    event FeesDistributed(uint256 indexed roundId);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 winnings);
    event RoundStateUpdated(uint256 indexed currentRoundId, RoundState state);
    event AgentDecisionSubmitted(uint256 indexed roundId, address agent, BetType betType);
    event MarketResolved(uint256 indexed roundId);
    event FeesUpdated(uint256 roomEntryFee);
    event RoundDurationUpdated(uint40 oldDuration, uint40 newDuration);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event PvpActionsUpdated(
        string indexed verb, PvpActionCategory indexed category, uint256 fee, uint32 duration, bool isNew, bool isUpdate
    );
    event PvpActionRemoved(string indexed verb);
    event PvpActionInvoked(string indexed verb, address indexed target, uint40 endTime, bytes parameters);

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

    constructor() Ownable(msg.sender) {
        // No initialization needed here since this is just the implementation
    }

    function initialize(
        address _gameMaster,
        address _token,
        address _creator,
        address _core,
        uint256 _roomEntryFee,
        address[] memory _initialAgents,
        address[] memory _initialAgentFeeRecipients,
        uint256[] memory _initialAgentIds
    ) external {
        if (initialized) {
            revert Room__AlreadyInitialized();
        }

        gameMaster = _gameMaster;
        token = _token;
        creator = _creator;
        core = payable(_core);
        fees = RoomFees({roomEntryFee: _roomEntryFee});
        pvpEnabled = true;
        for (uint256 i; i < _initialAgents.length; i++) {
            agentData[_initialAgents[i]] =
                RoomAgent({feeRecipient: _initialAgentFeeRecipients[i], coreId: _initialAgentIds[i], active: true});
            currentAgentCount++;
        }

        initialized = true;

        // Initialize the first round
        Round storage round = rounds[currentRoundId];
        round.state = RoundState.ACTIVE;
    }

    function addAgent(address agent) public onlyGameMasterOrCreator {
        if (activeAgents.length >= maxAgents) revert Room_MaxAgentsReached();
        if (agentData[agent].feeRecipient != address(0)) revert Room_AgentAlreadyExists();
        activeAgents.push(agent);
        emit AgentAdded(agent);
    }

    function removeAgent(address agent) public onlyGameMasterOrCreator {
        if (agentData[agent].feeRecipient == address(0)) revert Room_AgentNotExists(agent);
        agentData[agent].active = false;
        bool found = false;
        for (uint256 i; i < activeAgents.length; i++) {
            if (activeAgents[i] == agent) {
                activeAgents[i] = activeAgents[activeAgents.length - 1];
                activeAgents.pop();
                found = true;
                break;
            }
        }
        if (!found) revert Room_AgentNotExists(agent);
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

    function placeBet(address agent, BetType betType, uint256 amount) public payable nonReentrant {
        if (betType == BetType.KICK || betType == BetType.NONE) {
            revert Room_InvalidBetType();
        }

        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) {
            revert Room_RoundNotExpectedStatus(RoundState.ACTIVE, round.state);
        }
        if (agentData[agent].feeRecipient == address(0)) {
            revert Room_AgentNotActive(agent);
        }
        if (amount <= 0) {
            revert Room_InvalidAmount();
        }

        UserBet storage userBet = round.bets[msg.sender];
        AgentPosition storage position = round.agentPositions[agent];

        // Handle existing bet if there is one
        if (userBet.amount > 0) {
            // Remove old bet amounts from pools
            if (userBet.bettype == BetType.BUY) {
                position.buyPool -= userBet.amount;
            } else if (userBet.bettype == BetType.HOLD) {
                position.hold -= userBet.amount;
            } else if (userBet.bettype == BetType.SELL) {
                position.sell -= userBet.amount;
            }

            // Handle refund if new bet is smaller
            if (amount < userBet.amount) {
                uint256 refundAmount = userBet.amount - amount;
                (bool success,) = payable(msg.sender).call{value: refundAmount}("");
                if (!success) revert Room_TransferFailed();
            }

            // Verify additional payment if new bet is larger
            if (amount > userBet.amount) {
                if (msg.value != (amount - userBet.amount)) revert Room_InvalidAmount();
            }
        } else {
            // New bet
            if (msg.value != amount) revert Room_InvalidAmount();
        }

        // Update pools with new bet
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

    function claimWinnings(uint256 roundId) public nonReentrant {
        Round storage round = rounds[roundId];
        if (round.state != RoundState.CLOSED) revert Room_RoundNotClosed(roundId);
        if (round.bets[msg.sender].bettype == BetType.NONE) revert Room_SenderHasNoBetInRound();
        if (round.hasClaimedWinnings[msg.sender]) revert Room_SenderAlreadyClaimedWinnings();
        uint256 winnings = calculateWinnings(roundId, msg.sender);
        if (winnings == 0) revert Room_NoWinnings();

        round.hasClaimedWinnings[msg.sender] = true;
        (bool success,) = payable(msg.sender).call{value: winnings}("");
        if (!success) revert Room_TransferFailed();
        emit WinningsClaimed(roundId, msg.sender, winnings);
    }

    function calculateWinnings(uint256 roundId, address user) public view returns (uint256) {
        Round storage round = rounds[roundId];
        uint256 totalWinnings = 0;

        for (uint256 i; i < maxAgents; i++) {
            address agent = activeAgents[i];
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
            revert Room_RoundNotExpectedStatus(RoundState.INACTIVE, rounds[currentRoundId].state);
        }

        currentRoundId++;
        Round storage round = rounds[currentRoundId];
        round.startTime = uint40(block.timestamp);
        round.endTime = uint40(block.timestamp + roundDuration);
        round.state = RoundState.ACTIVE;

        emit RoundStarted(currentRoundId, round.startTime, round.endTime);
    }

    function submitAgentDecision(address agent, BetType decision) public onlyGameMaster {
        // Only game master or agent can call this function
        if (decision == BetType.NONE) revert Room_InvalidBetType();
        if (msg.sender != gameMaster) revert Room_NotAuthorized();

        // Only game master can submit the "KICK" decision
        if (decision == BetType.KICK /*&& msg.sender != gameMaster*/ ) revert Room_NotGameMaster();

        Round storage round = rounds[currentRoundId];
        // if (round.state != RoundState.PROCESSING) {
        //     revert Room_RoundNotExpectedStatus(RoundState.PROCESSING, round.state);
        // }
        AgentPosition storage position = round.agentPositions[agent];
        if (position.hasDecided) revert Room_AgentAlreadyDecided();
        position.decision = decision;
        position.hasDecided = true;
        emit AgentDecisionSubmitted(currentRoundId, agent, decision);
    }

    //TODO This function is broken,we should be refunding the user bets, the user is not an agent
    // function refundBets(uint256 roundId, address agent) internal {
    //     Round storage round = rounds[roundId];
    //     AgentPosition storage position = round.agentPositions[agent];
    //     if (!position.hasDecided) {
    //         for (uint256 i; i < activeAgents.length; i++) {
    //             address user = activeAgents[i];
    //             UserBet storage userBet = round.bets[user];
    //             if (userBet.bettype == BetType.BUY) {
    //                 (bool success,) = payable(user).call{value: userBet.amount}("");
    //                 if (!success) revert Room_TransferFailed();
    //             } else {
    //                 (bool success,) = payable(user).call{value: userBet.amount}("");
    //                 if (!success) revert Room_TransferFailed();
    //             }
    //         }
    //     }
    // }

    function resolveMarket() public {
        Round storage round = rounds[currentRoundId];
        _distributeFees(currentRoundId);
        round.state = RoundState.CLOSED;
        emit MarketResolved(currentRoundId);
    }

    function setCurrentRoundState(RoundState newState) external onlyGameMaster {
        Round storage round = rounds[currentRoundId];
        round.state = newState;
        emit RoundStateUpdated(currentRoundId, newState);
    }

    function _distributeFees(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        uint256 totalFees = round.totalFees;

        (,, uint256 roomCreatorPercent, uint256 agentCreatorPercent, uint256 daoPercent) = Core(payable(core)).getFees();
        uint256 basisPoint = Core(payable(core)).BASIS_POINTS();

        // Calculate cuts based on percentages (assuming BASIS_POINTS is 1000)
        // Creator: 2% = 20
        // Agent Creator: 2% = 20 
        // DAO: 1% = 10
        uint256 roomCreatorCut = (totalFees * roomCreatorPercent) / basisPoint;
        uint256 agentCreatorCut = (totalFees * agentCreatorPercent) / basisPoint;
        uint256 daoCut = (totalFees * daoPercent) / basisPoint;

        // Send room creator's cut
        (bool success1,) = payable(creator).call{value: roomCreatorCut}("");
        if (!success1) revert Room_TransferFailed();

        // Calculate agent creator share (divide equally among agents)
        uint256 agentCount = activeAgents.length;
        if (agentCount > 0) {
            uint256 agentCreatorShare = agentCreatorCut / agentCount;
            for (uint256 i = 0; i < agentCount; i++) {
                address agent = activeAgents[i];
                address feeRecipient = agentData[agent].feeRecipient;
                if (feeRecipient != address(0)) {
                    (bool success,) = payable(feeRecipient).call{value: agentCreatorShare}("");
                    if (!success) revert Room_TransferFailed();
                }
            }
        }

        // Send DAO cut
        address dao = Core(payable(core)).dao();
        (bool success2,) = payable(dao).call{value: daoCut}("");
        if (!success2) revert Room_TransferFailed();

        emit FeesDistributed(roundId);
    }
    function getTotalBets(uint256 roundId, address agent) public view returns (uint256 buyAmount,uint256 sellAmount, uint256 holfAmount){
        Round storage round = rounds[roundId];
        AgentPosition storage position = round.agentPositions[agent];
        return (position.buyPool, position.sell, position.hold);
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

    function getHasClaimedWinnings(uint256 roundId, address user) public view returns (bool) {
        return rounds[roundId].hasClaimedWinnings[user];
    }

    function updateSupportedPvpActions(string memory verb, PvpActionCategory category, uint256 fee, uint32 duration)
        external
        onlyGameMasterOrCreator
    {
        bool newAction = keccak256(abi.encodePacked(supportedPvpActions[verb].verb)) == keccak256(abi.encodePacked(""));

        supportedPvpActions[verb] = PvpAction({verb: verb, category: category, fee: fee, duration: duration});

        if (newAction) {
            supportedPvpVerbs.push(verb);
        }

        emit PvpActionsUpdated(verb, category, fee, duration, newAction, !newAction);
    }

    // TODO Commented to shave space
    // function removeSupportedPvpActions(string memory verb) external onlyGameMasterOrCreator {
    //     delete supportedPvpActions[verb];

    //     for (uint256 i = 0; i < supportedPvpVerbs.length; i++) {
    //         if (keccak256(abi.encodePacked(supportedPvpVerbs[i])) == keccak256(abi.encodePacked(verb))) {
    //             supportedPvpVerbs[i] = supportedPvpVerbs[supportedPvpVerbs.length - 1];
    //             supportedPvpVerbs.pop();
    //             break;
    //         }
    //     }

    //     emit PvpActionRemoved(verb);
    // }

    function invokePvpAction(address target, string memory verb, bytes memory parameters) public payable {
        if (parameters.length > 256) {
            revert Room_InvalidPvpAction();
        }

        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.ACTIVE) revert Room_RoundNotExpectedStatus(RoundState.ACTIVE, round.state);
        if (!pvpEnabled) {
            console2.log("PvP is disabled", pvpEnabled);
            revert Room_ActionNotSupported();
        }
        PvpAction memory action = supportedPvpActions[verb];
        if (keccak256(abi.encodePacked(action.verb)) == keccak256(abi.encodePacked(""))) {
            revert Room_InvalidPvpAction();
        }

        if (msg.value != action.fee) revert Room_InvalidAmount();

        PvpStatus[] storage targetStatuses = round.pvpStatuses[target];
        bool statusFound = false;
        uint256 expiredStatusIndex;

        for (uint256 i = 0; i < targetStatuses.length; i++) {
            if (keccak256(abi.encodePacked(targetStatuses[i].verb)) == keccak256(abi.encodePacked(verb))) {
                statusFound = true;
                if (targetStatuses[i].endTime > uint40(block.timestamp)) {
                    revert Room_StatusEffectAlreadyActive(verb, target, targetStatuses[i].endTime);
                }
                expiredStatusIndex = i;
                break;
            }
        }

        uint40 endTime = uint40(block.timestamp + action.duration);

        if (statusFound) {
            targetStatuses[expiredStatusIndex] =
                PvpStatus({verb: verb, instigator: msg.sender, endTime: endTime, parameters: parameters});
        } else {
            targetStatuses.push(
                PvpStatus({verb: verb, instigator: msg.sender, endTime: endTime, parameters: parameters})
            );
        }

        emit PvpActionInvoked(verb, target, endTime, parameters);
    }

    function getPvpStatuses(uint256 roundId, address agent) public view returns (PvpStatus[] memory) {
        return rounds[roundId].pvpStatuses[agent];
    }
    
    function changeRoundState(RoundState newState) public onlyGameMaster {
        Round storage round = rounds[currentRoundId];
        round.state = newState;
        emit RoundStateUpdated(currentRoundId, newState);
    }

    receive() external payable {}
}
