// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct DiamondStorage {
        mapping(bytes4 => address) facets;
        mapping(uint256 => address) selectorToFacetAndPosition;
        mapping(address => bool) supportedInterfaces;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
} 