// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Diamond.sol";
import "../src/facets/PvPFacet.sol";

contract DeployDiamond is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Diamond
        Diamond diamond = new Diamond();

        // Deploy PvP Facet
        PvPFacet pvpFacet = new PvPFacet();

        // Get function selectors for PvP Facet
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PvPFacet.updateSupportedPvpActions.selector;
        selectors[1] = PvPFacet.removeSupportedPvpActions.selector;
        selectors[2] = PvPFacet.invokePvpAction.selector;
        selectors[3] = PvPFacet.getSupportedPvpActions.selector;
        selectors[4] = PvPFacet.getPvpStatuses.selector;

        // Add PvP Facet to Diamond
        diamond.addFacet(address(pvpFacet), selectors);

        vm.stopBroadcast();
    }
}
