// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPvP.sol";

contract PvPFacet is IPvP {
    error Room_RoundInactive();
    error Room_ActionNotSupported();
    error Room_InvalidPvpAction();
    error Room_StatusEffectAlreadyActive(string verb, address target, uint40 endTime);

    // Storage layout must match the main contract
    struct DiamondStorage {
        mapping(uint256 => Round) rounds;
        uint256 currentRoundId;
        mapping(string => PvpAction) supportedPvpActions;
        string[] supportedPvpVerbs;
        bool pvpEnabled;
        IERC20 USDC;
        // ... other state variables from Room.sol that PvP functions need
    }

    struct Round {
        uint8 state; // RoundState enum
        uint40 startTime;
        uint40 endTime;
        bool pvpEnabled;
        mapping(string => PvpAction) supportedPvpActions;
        string[] supportedPvpVerbs;
        mapping(address => PvpStatus[]) pvpStatuses;
        // ... other Round struct fields
    }

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.storage.pvp");

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event PvpActionsUpdated(
        string indexed verb,
        PvpActionCategory indexed category,
        uint256 fee,
        uint32 duration,
        bool isNew,
        bool isUpdate
    );
    event PvpActionRemoved(string indexed verb);
    event PvpActionInvoked(string indexed verb, address indexed target, uint40 endTime, bytes parameters);

    function updateSupportedPvpActions(
        string memory verb,
        PvpActionCategory category,
        uint256 fee,
        uint32 duration
    ) external {
        DiamondStorage storage ds = diamondStorage();
        bool newAction = keccak256(abi.encodePacked(ds.supportedPvpActions[verb].verb)) == 
            keccak256(abi.encodePacked(""));

        ds.supportedPvpActions[verb] = PvpAction({
            verb: verb,
            category: category,
            fee: fee,
            duration: duration
        });

        if (newAction) {
            ds.supportedPvpVerbs.push(verb);
        }

        emit PvpActionsUpdated(verb, category, fee, duration, newAction, !newAction);
    }

    function removeSupportedPvpActions(string memory verb) external {
        DiamondStorage storage ds = diamondStorage();
        delete ds.supportedPvpActions[verb];

        for (uint256 i = 0; i < ds.supportedPvpVerbs.length; i++) {
            if (keccak256(abi.encodePacked(ds.supportedPvpVerbs[i])) == 
                keccak256(abi.encodePacked(verb))) {
                ds.supportedPvpVerbs[i] = ds.supportedPvpVerbs[ds.supportedPvpVerbs.length - 1];
                ds.supportedPvpVerbs.pop();
                break;
            }
        }

        emit PvpActionRemoved(verb);
    }

    function invokePvpAction(address target, string memory verb, bytes memory parameters) external {
        //Limit bytes to 256 bytes
        if (parameters.length > 256) {
            revert Room_InvalidPvpAction();
        }

        DiamondStorage storage ds = diamondStorage();
        Round storage round = ds.rounds[ds.currentRoundId];
        
        if (round.state != 1) revert Room_RoundInactive(); // 1 = ACTIVE
        if (!round.pvpEnabled) revert Room_ActionNotSupported();

        PvpAction memory action = round.supportedPvpActions[verb];
        if (keccak256(abi.encodePacked(action.verb)) == keccak256(abi.encodePacked(""))) {
            revert Room_InvalidPvpAction();
        }

        PvpStatus[] storage targetStatuses = round.pvpStatuses[target];
        bool statusFound = false;
        uint256 expiredStatusIndex;

        for (uint256 i = 0; i < targetStatuses.length; i++) {
            if (keccak256(abi.encodePacked(targetStatuses[i].verb)) == 
                keccak256(abi.encodePacked(verb))) {
                statusFound = true;
                if (targetStatuses[i].endTime > uint40(block.timestamp)) {
                    revert Room_StatusEffectAlreadyActive(
                        verb,
                        target,
                        targetStatuses[i].endTime
                    );
                }
                expiredStatusIndex = i;
                break;
            }
        }

        uint40 endTime = uint40(block.timestamp + action.duration);

        if (statusFound) {
            targetStatuses[expiredStatusIndex] = PvpStatus({
                verb: verb,
                instigator: msg.sender,
                endTime: endTime,
                parameters: parameters
            });
        } else {
            targetStatuses.push(PvpStatus({
                verb: verb,
                instigator: msg.sender,
                endTime: endTime,
                parameters: parameters
            }));
        }

        uint256 amount = action.fee;
        ds.USDC.transferFrom(msg.sender, address(this), amount);

        emit PvpActionInvoked(verb, target, endTime, parameters);
    }

    function getSupportedPvpActions() external view returns (PvpAction[] memory) {
        DiamondStorage storage ds = diamondStorage();
        PvpAction[] memory actions = new PvpAction[](ds.supportedPvpVerbs.length);

        for (uint256 i = 0; i < ds.supportedPvpVerbs.length; i++) {
            actions[i] = ds.supportedPvpActions[ds.supportedPvpVerbs[i]];
        }

        return actions;
    }

    function getPvpStatuses(uint256 roundId, address agent) external view returns (PvpStatus[] memory) {
        DiamondStorage storage ds = diamondStorage();
        return ds.rounds[roundId].pvpStatuses[agent];
    }
} 