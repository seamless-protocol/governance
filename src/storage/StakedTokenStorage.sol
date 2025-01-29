// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";

library StakedTokenStorage {
    struct Layout {
        /**
         * @notice interface for rewards controller
         */
        IRewardsController rewardsController;
        /**
         * @notice Amount of time user must wait before being able to withdraw
         */
        uint256 cooldownSeconds;
        /**
         * @notice Amount of time user has to withdraw once cooldown elapses
         */
        uint256 unstakeWindow;
        /**
         * @notice Maps user => timestamp they initiated a cooldown
         */
        mapping(address => uint256) stakersCooldowns;
    }

    bytes32 private constant STORAGE_SLOT = keccak256(
        abi.encode(uint256(keccak256("seamless.contracts.storage.StakedToken")) - 1)
    ) & ~bytes32(uint256(0xff));

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
