// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEmissionManager} from "@aave/periphery-v3/contracts/rewards/interfaces/IEmissionManager.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

library RewardKeeperStorage {
    struct Layout {
        /**
         * @notice interface for rewards controller
         */
        IRewardsController controller;

        /**
         * @notice interface for Aave V3 pool
         */
        IPool pool;

        /**
         * @notice interface for oracle contract
         * @dev only used for compatibility with rewards controller
         */
        IEACAggregatorProxy oracle;

        /**
         * @notice address of the asset token (i.e. SEAM)
         */
        address asset;

        /**
         * @notice address of the aToken treasury contract
         */
        address treasury;

        /**
         * @notice The amount of time between claims, i.e. 1 day
         */
        uint256 period;

        /**
         * @notice The previously set period
         */
        uint256 previousPeriod;

        /**
         * @notice holds the timestamp of the last time claim was called
         */
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
