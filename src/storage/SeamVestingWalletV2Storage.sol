// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {StakedToken} from "../StakedToken.sol";

abstract contract SeamVestingWalletV2Storage {
    /// @custom:storage-location erc7201:seamless.contracts.storage.SeamVestingWalletV2
    struct StorageLayout {
        /// @dev Address that receives the vested tokens
        address beneficiary;
        /// @dev ERC20 token that is being vested (SEAM)
        IERC20 token;
        /// @dev Reference to the staked token contract (stkSEAM)
        StakedToken stakedToken;
        /// @dev Amount of tokens already released to the beneficiary
        uint256 released;
        /// @dev Timestamp when vesting starts
        uint64 vestingStart;
        /// @dev Duration of the vesting period in seconds
        uint64 vestingDuration;
        /// @dev Cliff period in seconds before vesting begins
        uint64 vestingCliff;
        /// @dev Timestamp when the lockup period ends
        uint64 lockupEnd;
        /// @dev Amount of tokens currently staked
        uint256 stakedAmount;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamVestingWalletV2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x9e67e861de7e73ec70cbe3b3ca99dbc686516561816d16a16b4b31ec55c08700;

    function _getStorage() internal pure returns (StorageLayout storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }
}
