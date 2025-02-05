// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// TODO This
import {Script} from "forge-std/Script.sol";
import {Core} from "../src/Core.sol";
import {MockUSDC} from "./DeployMockUSDC.s.sol";

contract DeployCore is Script {
    function run() public returns (Core) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Deploy MockUSDC first
        vm.startBroadcast(deployerPrivateKey);
        MockUSDC usdc = new MockUSDC();
        Core core = new Core(address(usdc));
        vm.stopBroadcast();

        return core;
    }
}
