// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEmissionManager} from "@aave/periphery-v3/contracts/rewards/interfaces/IEmissionManager.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IStaticATokenFactory} from "static-a-token-v3/src/interfaces/IStaticATokenFactory.sol";

abstract contract RewardKeeperStorage {
    /// @custom:storage-location erc7201:seamless.contracts.storage.RewardKeeper
    struct StorageLayout {
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
         * @notice interface for the static AToken factory
         */
        IStaticATokenFactory staticATokenFactory;
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
        /**
         * @notice tracks which ERC20 tokens are allowed to have manual rate set
         */
        mapping(address => bool) allowedManualTokens;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.RewardKeeper")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x742aeba4ead5ca72041dc01c68b8b3a90b6c39143ae39b79915246ef39217200;

    function storageLayout() internal pure returns (StorageLayout storage l) {
        assembly {
            l.slot := STORAGE_SLOT
        }
    }
}
