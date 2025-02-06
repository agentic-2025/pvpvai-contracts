// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRoom {
    function initialize(
        address gameMaster,
        address token,
        address creator,
        address core,
        address usdc,
        uint256 roomEntryFee,
        address[] memory initialAgents,
        address diamond
    ) external;
}
