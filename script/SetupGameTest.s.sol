// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Core} from "../src/Core.sol";
import {MockUSDC} from "../src/test/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Room} from "../src/Room.sol";

contract SetupGameTest is Script {
    address public deployer;
    Core public core;
    MockUSDC public usdc;

    // Test accounts
    address public account1;
    address public account2;
    address public account3;
    uint256 public account1Key;
    uint256 public account2Key;
    uint256 public account3Key;

    // Generated agent wallets
    address public agentWallet1;
    address public agentWallet2;
    address public agentWallet3;
    uint256 public agentKey1;
    uint256 public agentKey2;
    uint256 public agentKey3;

    function setUp() public {
        // Add debug logging
        console2.log("Loading private keys from environment...");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        console2.log("Deployer key loaded:", deployerKey != 0);

        deployer = vm.addr(deployerKey);
        console2.log("Deployer address:", deployer);

        // Load accounts from environment with verification
        account1Key = vm.envUint("ACCOUNT1_PRIVATE_KEY");
        account2Key = vm.envUint("ACCOUNT2_PRIVATE_KEY");
        account3Key = vm.envUint("ACCOUNT3_PRIVATE_KEY");

        console2.log("Account keys loaded:");
        console2.log("Account1 key present:", account1Key != 0);
        console2.log("Account2 key present:", account2Key != 0);
        console2.log("Account3 key present:", account3Key != 0);

        account1 = vm.addr(account1Key);
        account2 = vm.addr(account2Key);
        account3 = vm.addr(account3Key);

        // agentKey1 = vm.envUint("AGENT1_PRIVATE_KEY");
        // agentKey2 = vm.envUint("AGENT2_PRIVATE_KEY");
        // agentKey3 = vm.envUint("AGENT3_PRIVATE_KEY");

        // console2.log("Agent keys loaded:");
        // console2.log("Agent1 key present:", agentKey1 != 0);
        // console2.log("Agent2 key present:", agentKey2 != 0);
        // console2.log("Agent3 key present:", agentKey3 != 0);

        // // Generate new agent wallet keys
        // // agentKey1 = uint256(keccak256(abi.encodePacked("agent1")));
        // // agentKey2 = uint256(keccak256(abi.encodePacked("agent2")));
        // // agentKey3 = uint256(keccak256(abi.encodePacked("agent3")));

        // agentWallet1 = vm.addr(0xa81946D14796875672FfC33381ad2be7D887D3EC);
        // agentWallet2 = vm.addr(0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d);
        // agentWallet3 = vm.addr(0x830598617569AfD7Ad16343f5D4a226578b16A3d);
    }

    function run() public {
        // 1. Deploy MockUSDC first
        vm.broadcast(deployer);
        usdc = new MockUSDC();
        console2.log("MockUSDC deployed at:", address(usdc));

        // Mint USDC to all accounts (1000 USDC each)
        uint256 mintAmount = 1000 * 10 ** 6; // 1000 USDC with 6 decimals

        vm.broadcast(deployer);
        usdc.mint(deployer, mintAmount);
        vm.broadcast(deployer);
        usdc.mint(account1, mintAmount);
        vm.broadcast(deployer);
        usdc.mint(account2, mintAmount);
        vm.broadcast(deployer);
        usdc.mint(account3, mintAmount);

        // 2. Deploy Core contract with real USDC address
        vm.broadcast(deployer);
        core = new Core(address(usdc));
        console2.log("Core deployed at:", address(core));
        console2.log("Core owner:", core.owner());
        console2.log("Deployer address:", deployer);

        // 2.5 Deploy Room implementation and set it in Core
        vm.broadcast(deployer);
        Room roomImplementation = new Room();
        console2.log("Room implementation deployed at:", address(roomImplementation));

        // Add diamond deployment here - wait for previous broadcast to complete
        vm.startBroadcast(deployer); // Use startBroadcast instead of multiple broadcasts
        // You'll need to deploy your diamond contract here
        address diamond = address(0); // Replace this with actual diamond deployment
        console2.log("Diamond deployed at:", diamond);

        core.setRoomImplementation(address(roomImplementation));
        console2.log("Room implementation set in Core");
        vm.stopBroadcast(); // Stop the broadcast before starting new ones

        // 3. Get fees
        (uint256 roomFee, uint256 agentFee,,,) = core.getFees();
        console2.log("Room creation fee:", roomFee);
        console2.log("Agent creation fee:", agentFee);

        // 4. Deposit fees for accounts
        vm.broadcast(account1);
        core.deposit{value: agentFee * 2}();

        vm.broadcast(account2);
        core.deposit{value: agentFee}();

        vm.broadcast(account3);
        core.deposit{value: agentFee}();

        // 5. Deposit room fee for account1
        vm.broadcast(account1);
        core.deposit{value: roomFee}();

        // 6. Create agents first (only owner can do this)
        vm.broadcast(deployer);
        core.createAgent{value: agentFee}(account1, 1);

        vm.broadcast(deployer);
        core.createAgent{value: agentFee}(account2, 2);

        vm.broadcast(deployer);
        core.createAgent{value: agentFee}(account3, 3);

        console2.log("\nAgents created");

        // 7. Log generated agent wallet details
        console2.log("\nGenerated Agent Wallet 1:");
        console2.log("Address:", 0xa81946D14796875672FfC33381ad2be7D887D3EC);
        // console2.log("Private Key:", agentKey1);

        console2.log("\nGenerated Agent Wallet 2:");
        console2.log("Address:", 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d);
        // console2.log("Private Key:", agentKey2);

        console2.log("\nGenerated Agent Wallet 3:");
        console2.log("Address:", 0x830598617569AfD7Ad16343f5D4a226578b16A3d);
        // console2.log("Private Key:", agentKey3);

        console2.log("\nCore contract owner:", core.owner());

        // 8. Register agent wallets using deployer account (Core owner)
        vm.broadcast(deployer);
        core.registerAgentWallet(1, 0xa81946D14796875672FfC33381ad2be7D887D3EC);
        vm.broadcast(deployer);
        core.registerAgentWallet(2, 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d);
        vm.broadcast(deployer);
        core.registerAgentWallet(3, 0x830598617569AfD7Ad16343f5D4a226578b16A3d);

        console2.log("\nAgent wallets registered");

        // 9. Create room with the three agent wallets
        address[] memory agentWallets = new address[](3);
        agentWallets[0] = 0xa81946D14796875672FfC33381ad2be7D887D3EC;
        agentWallets[1] = 0x4ffE2DF7B11ea3f28c6a7C90b39F52427c9D550d;
        agentWallets[2] = 0x830598617569AfD7Ad16343f5D4a226578b16A3d;

        console2.log("\nCreating room with the three agent wallets");
        vm.broadcast(deployer);
        address roomAddress = core.createRoom(
            deployer, // gameMaster
            account1, // creator
            address(usdc), // token address
            agentWallets,
            diamond // Add diamond address here
        );

        console2.log("\nRoom created at:", roomAddress);
    }
}
