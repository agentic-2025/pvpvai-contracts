// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRoom {
    function initialize(
        address gameMaster,
        address token,
        address creator,
        address core,
        address[] memory initialAgents,
        address[] memory initialAgentFeeRecipients,
        uint256[] memory initialAgentIds
    ) external;
}
