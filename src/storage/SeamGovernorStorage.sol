// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";

library SeamGovernorStorage {
    /// @custom:storage-location erc7201:seamless.contracts.storage.SeamGovernor
    struct Layout {
        IERC5805 esSEAM;
        IERC5805 stkSEAM;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamGovernor")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x144cecdd5032feb0414f3a11eeaffb078bc29f44e1797be01e37f8dd49c78500;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
