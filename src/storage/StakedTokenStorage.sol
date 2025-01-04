// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "../safetyModule/interfaces/IRewardsController.sol";

library StakedTokenStorage {

    struct Layout {
        IRewardsController rewardsController;
        bytes32 MANAGER_ROLE;
        bytes32 UPGRADER_ROLE;
        bool isEmergencyWithdrawal;
        uint256 COOLDOWN_SECONDS;
        uint256 UNSTAKE_WINDOW;
        mapping(address => uint256) stakersCooldowns;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.EscrowSeam")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.StakedToken")) - 1)) & ~bytes32(uint256(0xff));

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}