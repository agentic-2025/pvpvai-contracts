// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

// import {Script} from "forge-std/Script.sol";
// import {Core} from "../src/Core.sol";

// contract CreateAgent is Script {
//     function run(address coreAddress, address agentAddress) public {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         Core core = Core(payable(coreAddress));

//         vm.startBroadcast(deployerPrivateKey);
//         // Get agent creation fee from core contract
//         (, uint256 agentCreationFee,,,) = core.getFees();
//         // Create agent
//         core.createAgent{value: agentCreationFee}(agentAddress);
//         vm.stopBroadcast();
//     }
// }
