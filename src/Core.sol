//SPDX-License-Identifier : MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Room.sol";

// Core contract managing agent creation, permissions, fees, and registry

contract Core is Ownable {
    error Core__FeeZero();
    error Core__InvalidCutPoints();
    error Core__InvalidCutRate();
    error Core__InvalidCreator();
    error Core__IncorrectAgentCreationFee();
    error Core__IncorrectRoomCreationFee();
    error Core__AgentAlreadyExists();
    error Core__InsufficientBalance();
    error Core__UnauthorizedAccessofAgent();
    error Core__UnauthorizedAccessofRoom();
    error Core__AgentNotActive(address agent);
    error Core__AgentDoesNotExist(address agent);
    error Core__InvalidRoomAgents();
    struct FeeStructure {
        uint256 agentCreationFee;
        uint256 roomCreationFee;
        uint256 roomCreatorCut; //basis points
        uint256 agentCreatorCut; //basis points
        uint256 daoCut; //basis points
    }

    struct Agent {
        address Creator;
        bool isActive;
    }

    struct RoomStructure {
        address token;
        address creator;
        bool isActive;
    }

    address public dao;
    uint256 public constant MAX_FEE_RATE = 1000;
    uint256 public constant BASIS_POINTS = 1000;
    FeeStructure public fees;
    mapping(address => RoomStructure) public rooms;
    mapping(address => Agent) public agents;
    mapping(address => uint256) public Balances; //useraddress -> balance
    address public immutable USDC;

    event FeesSet(
        uint256 indexed roomCreationFee,
        uint256 indexed agentCreationFee,
        uint256 indexed roomCreatorCut,
        uint256 agentCreatorCut,
        uint256 daoCut
    ); //can it be tracked without indexed?
    event AgentUpdated(address indexed agentAddress, address indexed creator, bool indexed isActive);
    event RoomCreated(address indexed roomAddress, address indexed creator);
    event AgentCreated(address indexed agentAddress, address indexed creator);
    event BalanceWithdrawn(address indexed user, uint256 indexed amount);
    event RoomUpdated(address indexed roomAddress, address indexed creator, bool indexed isActive);

    constructor(address usdc) Ownable(msg.sender) {
        //owner is admin of dao
        USDC = usdc;
        fees = FeeStructure({
            agentCreationFee: 0.001 ether,
            roomCreationFee: 0.005 ether,
            roomCreatorCut: 1000,
            agentCreatorCut: 200,
            daoCut: 200 //platform fee/ dao fee
        });
    }

    receive() external payable {}
    fallback() external {}

    //agent functions
    function createAgent(address agentAddress) external payable {
        if (msg.value != fees.agentCreationFee) {
            revert Core__IncorrectAgentCreationFee();
        }
        agents[agentAddress] = Agent({Creator: msg.sender, isActive: true});
        _distributeFees(fees.agentCreationFee);

        emit AgentCreated(agentAddress, msg.sender);
    }

    function UpdateAgent(address agentAddress, bool isactive, address creator) external {
        if (agents[agentAddress].Creator != msg.sender) {
            revert Core__UnauthorizedAccessofAgent();
        } //check agent address? //can owner change agent status
        agents[agentAddress].isActive = isactive;
        agents[agentAddress].Creator = creator;

        emit AgentUpdated(agentAddress, creator, isactive);
    }

    function setFee(
        uint256 roomcreationFee,
        uint256 agentcreationFee,
        uint256 roomcreatorCut,
        uint256 agentcreatorCut,
        uint256 daocut
    ) public onlyOwner {
        if (roomcreationFee <= 0 || agentcreationFee <= 0 || roomcreatorCut < 0 || agentcreatorCut < 0 || daocut < 0) {
            revert Core__FeeZero();
        }
        if (roomcreatorCut + agentcreatorCut + daocut != BASIS_POINTS) {
            revert Core__InvalidCutPoints();
        }
        if (roomcreatorCut > MAX_FEE_RATE || agentcreatorCut > MAX_FEE_RATE || daocut > MAX_FEE_RATE) {
            revert Core__InvalidCutRate();
        }

        fees.roomCreationFee = roomcreationFee; //fee in wei
        fees.agentCreationFee = agentcreationFee; //fee in wei
        fees.roomCreatorCut = roomcreatorCut;
        fees.agentCreatorCut = agentcreatorCut;
        fees.daoCut = daocut;
        emit FeesSet(roomcreationFee, agentcreationFee, roomcreatorCut, agentcreatorCut, daocut);
    }

    function setDao(address daoAddress) external onlyOwner {
        dao = daoAddress;
    }

    function _distributeFees(uint256 amount) internal {
        Balances[dao] += amount;
    }

    function UpdateOwner(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
    }

    function withdrawBalance() external {
        uint256 amount = Balances[msg.sender];
        if (amount <= 0) {
            revert Core__InsufficientBalance();
        }
        Balances[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed.");

        emit BalanceWithdrawn(msg.sender, amount);
    }
    //room

    function createRoom(address tokenAddress, address[] memory roomAgents) external payable returns (address) {
        if (roomAgents.length == 0) {
            revert Core__InvalidRoomAgents();
        }
        if (roomAgents.length > 5) {
            revert Core__InvalidRoomAgents();
        }
        if (msg.value != fees.roomCreationFee) { 
            revert Core__IncorrectRoomCreationFee();
        }

        // Verify all agents exist and are active
        for (uint256 i = 0; i < roomAgents.length; i++) {
            if (agents[roomAgents[i]].Creator == address(0)) {
                revert Core__AgentDoesNotExist(roomAgents[i]);
            }
            if (!agents[roomAgents[i]].isActive) {
                revert Core__AgentNotActive(roomAgents[i]);
            }
        }

        Room newRoom = new  Room(
            tokenAddress,
            msg.sender,
            address(this),
            roomAgents,
            USDC,
            0.01 ether, // roomEntryFee
            0.01 ether, // messageInjectionFee
            0.01 ether // muteForaMinuteFee
        );

        RoomStructure memory room = RoomStructure({token: tokenAddress, creator: msg.sender, isActive: true});
        rooms[address(newRoom)] = room;

        _distributeFees(fees.roomCreationFee);

        emit RoomCreated(address(newRoom), msg.sender);
        return address(newRoom);
    }

    function updateRoom(address roomAddress, bool isactive, address creator) external {
        if (rooms[roomAddress].creator != msg.sender) {
            revert Core__UnauthorizedAccessofRoom();
        }
        rooms[roomAddress].isActive = isactive;
        rooms[roomAddress].creator = creator;

        emit RoomUpdated(roomAddress, creator, isactive);
    }

    //getters
    function getRoom(address roomAddress) external view returns (address, address, bool) {
        return (rooms[roomAddress].token, rooms[roomAddress].creator, rooms[roomAddress].isActive);
    }

    function getAgent(address agentAddress) external view returns (address, bool) {
        return (agents[agentAddress].Creator, agents[agentAddress].isActive);
    }

    function getFees() external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (fees.roomCreationFee, fees.agentCreationFee, fees.roomCreatorCut, fees.agentCreatorCut, fees.daoCut);
    }

    function getBalance(address user) external view returns (uint256) {
        return Balances[user];
    }
}
