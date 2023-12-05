// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

library SeamEmissionManagerStorage {
    struct Layout {
        IERC20 seam;
        uint256 emissionPerSecond;
        uint64 lastClaimedTimestamp;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamEmissionManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x499527223a0cbf0f8120b81b4a5c3bfc177472cf818369c98e27b6304d0f5000;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
