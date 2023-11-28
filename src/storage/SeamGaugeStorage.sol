// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

library SeamGaugeStorage {
    struct CategoryConfig {
        // Desription of category, e.g. "ILM LPs"
        string description;
        // Minimum percentage of emission for this category, once set it cannot be modified
        uint256 minPercentage;
        // Maximum percentage of emission for this category, once set it cannot be modified
        uint256 maxPercentage;
        // Actual current percentage of emission for this category, can be modified within min/max bounds
        uint256 percentage;
        // Timestamp of last claimed emission for this category
        uint64 lastClaimedTimestamp;
        // Address of receiver of emission for this category
        address receiver;
    }

    struct Layout {
        IERC20 seam;
        uint256 emissionPerSecond;
        CategoryConfig[] categories;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamGauge")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x499527223a0cbf0f8120b81b4a5c3bfc177472cf818369c98e27b6304d0f5000;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
