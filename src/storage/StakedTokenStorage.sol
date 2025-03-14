// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {Checkpoints} from "openzeppelin-contracts/utils/structs/Checkpoints.sol";

abstract contract StakedTokenStorage {
    /// @custom:storage-location erc7201:seamless.contracts.storage.StakedToken
    struct StorageLayout {
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
        /**
         * @notice Checkpoints for asset balance
         */
        Checkpoints.Trace208 assetBalanceCheckpoints;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.StakedToken")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_SLOT = 0x70e6a77d3948d1d16db6a5474690147c8b32b65a8dc6d1ba6210b5bdedf84200;

    function storageLayout() internal pure returns (StorageLayout storage l) {
        assembly {
            l.slot := STORAGE_SLOT
        }
    }
}
