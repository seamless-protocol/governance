// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEmissionManager} from "@aave/periphery-v3/contracts/rewards/interfaces/IEmissionManager.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

library RewardKeeperStorage {
    struct Layout {
        IEmissionManager manager;
        IRewardsController controller;
        IPool pool;
        address treasury;
        address asset;
        uint256 period;
        uint256 previousPeriod;
        uint256 lastClaim;
    }

    bytes32 private constant STORAGE_SLOT = keccak256(
        abi.encode(uint256(keccak256("seamless.contracts.storage.RewardKeeper")) - 1)
    ) & ~bytes32(uint256(0xff));

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
