// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Checkpoints} from "openzeppelin-contracts/utils/structs/Checkpoints.sol";

library GovernorCountingFractionStorage {
    struct Layout {
        Checkpoints.Trace208 voteCountNumeratorHistory;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.GovernorCountingFraction")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0xbb59bc16b5fc3068f9f2430313a61d2869d28b2c4b4f58bcf226eb189311be00;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
