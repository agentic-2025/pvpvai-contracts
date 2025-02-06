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
    function getSupportedPvpActions() external view returns (PvpAction[] memory);
    function getPvpStatuses(uint256 roundId, address agent) external view returns (PvpStatus[] memory);
    function updateRoundState(uint256 roundId, uint8 state) external;
    function startRound(uint256 roundId) external;
    function setGlobalPvpEnabled(bool enabled) external;
}
