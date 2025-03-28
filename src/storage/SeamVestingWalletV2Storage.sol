// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {StakedToken} from "../StakedToken.sol";

abstract contract SeamVestingWalletV2Storage {
    /// @custom:storage-location erc7201:seamless.contracts.storage.SeamVestingWalletV2
    struct Layout {
        // Core vesting data
        address beneficiary;
        IERC20 token;
        uint256 released;
        uint64 vestingStart;
        uint64 vestingDuration;
        uint64 vestingCliff;
        // Lockup period data
        uint64 lockupStart;
        uint64 lockupEnd;
        // Staking data
        StakedToken stakedToken;
        uint256 stakedAmount;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamVestingWalletV2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x9e67e861de7e73ec70cbe3b3ca99dbc686516561816d16a16b4b31ec55c08700;

    function _getStorage() internal pure returns (Layout storage l) {
        assembly {
            l.slot := STORAGE_SLOT
        }
    }
}
