//SPDX-License-Identifier : MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IRoom.sol";
import "forge-std/console2.sol";
// Core contract managing agent creation, permissions, fees, and registry

contract Core is Ownable, ReentrancyGuard {
    error Core__FeeZero();
    error Core__InvalidCutPoints();
    error Core__InvalidCutRate();
    error Core__InvalidCreator();
    error Core__IncorrectAgentCreationFee();
    error Core__IncorrectRoomCreationFee();
    error Core__AgentAlreadyExists(uint256 agentId);
    error Core__InsufficientBalance();
    error Core__UnauthorizedAccessofAgent();
    error Core__UnauthorizedAccessofRoom();
    error Core__AgentNotActive(uint256 agentId);
    error Core__AgentDoesNotExist(uint256 agentId);
    error Core__InvalidRoomAgents();
    error Core__CreateRoomUnathorized();
    error Core__CreateRoomInvalidToken();
    error Core__AgentAltWalletAlreadyExists();
    error Core__AgentWalletNotFound(address queriedWallet);
    error Core__RoomImplementationNotSet();

    struct FeeStructure {
        uint256 agentCreationFee;
        uint256 roomCreationFee;
        uint256 roomCreatorCut; //basis points
        uint256 agentCreatorCut; //basis points
        uint256 daoCut; //basis points
    }

    struct Agent {
        address creator;
        bool isActive;
        address[] wallets; //convenience field
        address[] rooms; //convenience field
    }

    struct RoomStructure {
        address token;
        address creator;
        bool isActive; // When true,
    }

    address public dao;
    uint32 public maxAgentsPerRoom = 5;
    uint256 public constant MAX_FEE_RATE = 1000;
    uint256 public constant BASIS_POINTS = 10000;
    FeeStructure public fees;
    mapping(address => RoomStructure) public rooms;
    mapping(uint256 => Agent) public agents;
    mapping(address => uint256) public agentWallets;
    mapping(address => uint256) public balances; //useraddress -> balance, updated when we distribute fees

    // Alternate wallets for the agent to sandbox spending in trading rooms, input address is the alt, what you receive is the agent wallet
    address public immutable USDC;

    event FeesSet(
        uint256 indexed roomCreationFee,
        uint256 indexed agentCreationFee,
        uint256 indexed roomCreatorCut,
        uint256 agentCreatorCut,
        uint256 daoCut
    ); //can it be tracked without indexed?
    event RoomCreated(address indexed roomAddress, address indexed creator);
    event RoomUpdated(address indexed roomAddress, address indexed creator, bool indexed isActive);
    event AgentCreated(uint256 indexed agentId, address indexed creator);
    event AgentUpdated(uint256 indexed agentId, address indexed creator, bool isActive);
    event AgentWalletsUpdated(uint256 indexed agentId, address indexed newWallet);
    event BalanceWithdrawn(address indexed user, uint256 indexed amount);
    event BalanceDeposited(address indexed user, uint256 indexed amount);

    constructor(address usdc) Ownable(msg.sender) {
        //owner is admin of dao
        USDC = usdc;
        fees = FeeStructure({
            agentCreationFee: 0.002 ether,
            roomCreationFee: 0.001 ether,
            roomCreatorCut: 100,
            agentCreatorCut: 200,
            daoCut: 200 //platform fee/ dao fee
        });
    }

    receive() external payable {}
    fallback() external {}

    //agent functions
    function createAgent(address creator, uint256 agentId) external payable onlyOwner {
        // Check that the creator has enough balance to cover the agent creation fee
        if (balances[creator] < fees.agentCreationFee) {
            revert Core__InsufficientBalance();
        }
        if (msg.value != fees.agentCreationFee) {
            revert Core__IncorrectAgentCreationFee();
        }

        // Check that the agentId is not already in use

        if (agents[agentId].creator != address(0)) {
            revert Core__AgentAlreadyExists(agentId);
        }

        // Create the agent
        agents[agentId] =
            Agent({creator: msg.sender, isActive: true, wallets: new address[](0), rooms: new address[](0)});
        // Decrement the creator's balance by the agent creation fee and add fee to dao balance
        balances[creator] -= fees.agentCreationFee;
        _distributeFees(fees.agentCreationFee);

        emit AgentCreated(agentId, msg.sender);
    }

    function UpdateAgent(uint256 agentId, bool isactive) external {
        if (agents[agentId].creator != msg.sender && msg.sender != owner()) {
            revert Core__UnauthorizedAccessofAgent();
        } //check agent address? //can owner change agent status
        agents[agentId].isActive = isactive;

        emit AgentUpdated(agentId, msg.sender, isactive);
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
        balances[dao] += amount;
    }

    function withdrawBalance() external nonReentrant {
        uint256 amount = balances[msg.sender];
        if (amount <= 0) {
            revert Core__InsufficientBalance();
        }
        balances[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed.");

        emit BalanceWithdrawn(msg.sender, amount);
    }

    function createRoom(
        address gameMaster,
        address creator,
        address tokenAddress,
        address[] memory roomAgentWallets,
        address[] memory roomAgentFeeRecipients,
        uint256[] memory roomAgentIds,
        address roomImplementation
    ) external payable onlyOwner returns (address) {
        // Check if the token address is a valid ERC20 tokenAddress
        // TODO shallow check, should check all functions that are needed for real trading
        // try IERC20(tokenAddress).totalSupply() returns (uint256) {}
        // catch {
        //     revert Core__CreateRoomInvalidToken();
        // }

        // Check if there is enough balance for creator to cover the room creation fee
        console2.log("Checking balance for room creation fee");
        if (balances[creator] < fees.roomCreationFee) {
            console2.log("Insufficient balance for room creation fee");
            revert Core__InsufficientBalance();
        }
        console2.log("Checking if there is at least one agent");
        // Check if there is at least one agent
        if (roomAgentWallets.length == 0) {
            console2.log("No agents provided");
            revert Core__InvalidRoomAgents();
        }
        console2.log("Checking if there are too many agents");
        if (roomAgentWallets.length > maxAgentsPerRoom) {
            console2.log("Too many agents provided");
            revert Core__InvalidRoomAgents();
        }
        console2.log("Checking if all agents are valid");
        for (uint256 i = 0; i < roomAgentWallets.length; i++) {
            address agentAddress = roomAgentWallets[i];
            console2.log("Checking agent wallet");

            (uint256 agentId, bool isActive,) = getAgentByWallet(agentAddress);
            if (agentId == 0) {
                console2.log("Agent wallet not found");
                revert Core__AgentWalletNotFound(agentAddress);
            }
            if (!isActive) {
                console2.log("Agent not active");
                revert Core__AgentNotActive(agentId);
            }
        }
        console2.log("All agents are valid");

        // Deploy minimal proxy clone of the room implementation
        address newRoom = Clones.clone(roomImplementation);
        console2.log("Cloned room implementation, now initializing");
        // Initialize the room with diamond address
        IRoom(newRoom).initialize(
            gameMaster,
            tokenAddress,
            creator,
            address(this),
            0.01 ether, // roomEntryFee
            roomAgentWallets,
            roomAgentFeeRecipients,
            roomAgentIds
        );

        RoomStructure memory room = RoomStructure({
            token: tokenAddress,
            creator: creator, // Fix: use creator parameter instead of msg.sender
            isActive: true
        });
        rooms[newRoom] = room;

        //Transfer the room creation fee to the dao
        balances[creator] -= fees.roomCreationFee;
        balances[dao] += fees.roomCreationFee;

        emit RoomCreated(newRoom, creator);
        return newRoom;
    }

    function updateRoom(address roomAddress, bool isactive, address newCreator) external {
        address roomCreator = rooms[roomAddress].creator;

        if (msg.sender == owner()) {
            // Admin can only change active status, not transfer ownership
            if (newCreator != roomCreator) {
                revert Core__UnauthorizedAccessofRoom();
            }
            rooms[roomAddress].isActive = isactive;
        } else if (msg.sender == roomCreator) {
            // Room creator can change both status and transfer ownership
            rooms[roomAddress].isActive = isactive;
            rooms[roomAddress].creator = newCreator;
        } else {
            revert Core__UnauthorizedAccessofRoom();
        }

        emit RoomUpdated(roomAddress, newCreator, isactive);
    }

    function registerAgentWallet(uint256 agentId, address altWallet) external onlyOwner {
        if (agents[agentId].creator == address(0)) {
            revert Core__AgentDoesNotExist(agentId);
        }
        if (agentWallets[altWallet] != 0) {
            revert Core__AgentAltWalletAlreadyExists();
        }
        agentWallets[altWallet] = agentId;
        agents[agentId].wallets.push(altWallet);
        emit AgentWalletsUpdated(agentId, altWallet);
    }
    //returns agentId, isActive, creatorAddress

    function getAgentByWallet(address wallet) public view returns (uint256, bool, address) {
        uint256 agentId = agentWallets[wallet];
        console2.log("Getting agent by wallet");
        console2.log("Agent ID:", agentId);
        console2.log("Is Active:", agents[agentId].isActive);
        console2.log("Creator:", agents[agentId].creator);
        return (agentId, agents[agentId].isActive, agents[agentId].creator); //if you get a 0 address, no agent found
    }

    //getters
    function getRoom(address roomAddress) external view returns (address, address, bool) {
        return (rooms[roomAddress].token, rooms[roomAddress].creator, rooms[roomAddress].isActive);
    }

    function getAgent(uint256 agentId) external view returns (address, bool, address[] memory, address[] memory) {
        return (agents[agentId].creator, agents[agentId].isActive, agents[agentId].wallets, agents[agentId].rooms);
    }

    function getFees() external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (fees.roomCreationFee, fees.agentCreationFee, fees.roomCreatorCut, fees.agentCreatorCut, fees.daoCut);
    }

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function deposit() external payable {
        if (msg.value <= 0) {
            revert Core__FeeZero();
        }

        balances[msg.sender] += msg.value;

        emit BalanceDeposited(msg.sender, msg.value);
    }
}
