// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

library SeamTimelockControllerStorage {
    struct Layout {
        uint256 minDelay;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamTimelockController")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x263ed6143c54408ffb31ea73e81969b42f560e7b9104812b019a9e78ab9b3c00;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
