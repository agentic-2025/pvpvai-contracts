// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPvP.sol";
import "forge-std/console2.sol";

contract PvPFacet is IPvP {
    error PvPFacet_RoundInactive();
    error PvPFacet_ActionNotSupported();
    error PvPFacet_InvalidPvpAction();
    error PvPFacet_StatusEffectAlreadyActive(string verb, address target, uint40 endTime);

    // Storage layout must match the main contract
    struct DiamondStorage {
        mapping(uint256 => Round) rounds;
        uint256 currentRoundId;
        // Global config
        mapping(string => PvpAction) globalSupportedPvpActions;
        string[] globalSupportedPvpVerbs;
        bool globalPvpEnabled;
        IERC20 USDC;
    }

    struct Round {
        uint8 state; // RoundState enum
        uint40 startTime;
        uint40 endTime;
        mapping(address => PvpStatus[]) pvpStatuses;
    }

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.storage.pvp");

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event PvpActionsUpdated(
        string indexed verb, PvpActionCategory indexed category, uint256 fee, uint32 duration, bool isNew, bool isUpdate
    );
    event PvpActionRemoved(string indexed verb);
    event PvpActionInvoked(string indexed verb, address indexed target, uint40 endTime, bytes parameters);

    function setGlobalPvpEnabled(bool enabled) external {
        DiamondStorage storage ds = diamondStorage();
        ds.globalPvpEnabled = enabled;
    }

    function startRound(uint256 roundId) external {
        DiamondStorage storage ds = diamondStorage();
        Round storage round = ds.rounds[roundId];

        // Only initialize round timing state
        round.startTime = uint40(block.timestamp);
        round.state = 1; // ACTIVE
    }

    function updateGlobalSupportedPvpActions(
        string memory verb,
        PvpActionCategory category,
        uint256 fee,
        uint32 duration
    ) external {
        DiamondStorage storage ds = diamondStorage();
        bool newAction =
            keccak256(abi.encodePacked(ds.globalSupportedPvpActions[verb].verb)) == keccak256(abi.encodePacked(""));

        ds.globalSupportedPvpActions[verb] = PvpAction({verb: verb, category: category, fee: fee, duration: duration});

        if (newAction) {
            ds.globalSupportedPvpVerbs.push(verb);
        }

        emit PvpActionsUpdated(verb, category, fee, duration, newAction, !newAction);
    }

    function removeGlobalSupportedPvpActions(string memory verb) external {
        DiamondStorage storage ds = diamondStorage();
        delete ds.globalSupportedPvpActions[verb];

        for (uint256 i = 0; i < ds.globalSupportedPvpVerbs.length; i++) {
            if (keccak256(abi.encodePacked(ds.globalSupportedPvpVerbs[i])) == keccak256(abi.encodePacked(verb))) {
                ds.globalSupportedPvpVerbs[i] = ds.globalSupportedPvpVerbs[ds.globalSupportedPvpVerbs.length - 1];
                ds.globalSupportedPvpVerbs.pop();
                break;
            }
        }

        emit PvpActionRemoved(verb);
    }

    function invokePvpAction(address target, string memory verb, bytes memory parameters) external {
        console2.log("(PvPFacet) Invoking PvP action", verb, "on ", target);
        if (parameters.length > 256) {
            console2.log("(PvPFacet) Parameters length is greater than 256 bytes");
            revert PvPFacet_InvalidPvpAction();
        }

        DiamondStorage storage ds = diamondStorage();
        Round storage round = ds.rounds[ds.currentRoundId];

        if (round.state != 1) revert PvPFacet_RoundInactive(); // 1 = ACTIVE
        if (!ds.globalPvpEnabled) revert PvPFacet_ActionNotSupported();

        PvpAction memory action = ds.globalSupportedPvpActions[verb];
        if (keccak256(abi.encodePacked(action.verb)) == keccak256(abi.encodePacked(""))) {
            revert PvPFacet_InvalidPvpAction();
        }

        PvpStatus[] storage targetStatuses = round.pvpStatuses[target];
        bool statusFound = false;
        uint256 expiredStatusIndex;

        for (uint256 i = 0; i < targetStatuses.length; i++) {
            if (keccak256(abi.encodePacked(targetStatuses[i].verb)) == keccak256(abi.encodePacked(verb))) {
                statusFound = true;
                if (targetStatuses[i].endTime > uint40(block.timestamp)) {
                    revert PvPFacet_StatusEffectAlreadyActive(verb, target, targetStatuses[i].endTime);
                }
                expiredStatusIndex = i;
                break;
            }
        }

        uint40 endTime = uint40(block.timestamp + action.duration);

        if (statusFound) {
            targetStatuses[expiredStatusIndex] =
                PvpStatus({verb: verb, instigator: msg.sender, endTime: endTime, parameters: parameters});
        } else {
            targetStatuses.push(
                PvpStatus({verb: verb, instigator: msg.sender, endTime: endTime, parameters: parameters})
            );
        }

        ds.USDC.transferFrom(msg.sender, address(this), action.fee);
        emit PvpActionInvoked(verb, target, endTime, parameters);
    }

    function getGlobalSupportedPvpActions() external view returns (PvpAction[] memory) {
        DiamondStorage storage ds = diamondStorage();
        PvpAction[] memory actions = new PvpAction[](ds.globalSupportedPvpVerbs.length);

        for (uint256 i = 0; i < ds.globalSupportedPvpVerbs.length; i++) {
            actions[i] = ds.globalSupportedPvpActions[ds.globalSupportedPvpVerbs[i]];
        }

        return actions;
    }

    function getPvpStatuses(uint256 roundId, address agent) external view returns (PvpStatus[] memory) {
        DiamondStorage storage ds = diamondStorage();
        return ds.rounds[roundId].pvpStatuses[agent];
    }

    function updateRoundState(uint256 roundId, uint8 state) external {
        DiamondStorage storage ds = diamondStorage();
        Round storage round = ds.rounds[roundId];
        round.state = state;
    }

    function updatePvpEnabled(uint256 roundId, bool enabled) external {
        DiamondStorage storage ds = diamondStorage();
        ds.globalPvpEnabled = enabled;
    }

    // Add new getters
    function getRoundState(uint256 roundId)
        external
        view
        returns (uint8 state, uint40 startTime, uint40 endTime, uint256 numSupportedActions, uint256 numActiveStatuses)
    {
        DiamondStorage storage ds = diamondStorage();
        Round storage round = ds.rounds[roundId];

        return (
            round.state,
            round.startTime,
            round.endTime,
            ds.globalSupportedPvpVerbs.length,
            0 // TODO: Add count of active statuses if needed
        );
    }

    function getCurrentRoundId() external view returns (uint256) {
        DiamondStorage storage ds = diamondStorage();
        return ds.currentRoundId;
    }
}
