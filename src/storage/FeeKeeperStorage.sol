// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "aave-v3-periphery/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {IFeeSource} from "../interfaces/IFeeSource.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

abstract contract FeeKeeperStorage {
    /// @custom:storage-location erc7201:seamless.contracts.storage.FeeKeeper
    struct StorageLayout {
        /**
         * @notice interface for rewards controller
         */
        IRewardsController controller;
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
         * @notice tracks all fee sources
         */
        EnumerableSet.AddressSet feeSources;
        /**
         * @notice tracks which ERC20 tokens are allowed to have manual rate set
         */
        mapping(address => bool) allowedManualTokens;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.FeeKeeper")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x29cf5840689afee1618424aac5f0d53f633eccda428e21b9158c2a487c865b00;

    function storageLayout() internal pure returns (StorageLayout storage l) {
        assembly {
            l.slot := STORAGE_SLOT
        }
    }
}
