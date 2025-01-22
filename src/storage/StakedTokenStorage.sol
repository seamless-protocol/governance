// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";

library StakedTokenStorage {
    struct Layout {
        IRewardsController rewardsController;
        uint256 cooldownSeconds;
        uint256 unstakeWindow;
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
