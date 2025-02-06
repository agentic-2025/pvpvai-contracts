// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPvP {
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

    function invokePvpAction(address target, string memory verb, bytes memory parameters) external;
    function getGlobalSupportedPvpActions() external view returns (PvpAction[] memory);
    function getPvpStatuses(uint256 roundId, address agent) external view returns (PvpStatus[] memory);
    function updateRoundState(uint256 roundId, uint8 state) external;
    function startRound(uint256 roundId) external;
    function setGlobalPvpEnabled(bool enabled) external;
    function updateGlobalSupportedPvpActions(
        string memory verb,
        PvpActionCategory category,
        uint256 fee,
        uint32 duration
    ) external;
    function removeGlobalSupportedPvpActions(string memory verb) external;
    function getRoundState(uint256 roundId)
        external
        view
        returns (uint8 state, uint40 startTime, uint40 endTime, uint256 numSupportedActions, uint256 numActiveStatuses);
    function getCurrentRoundId() external view returns (uint256);
}
