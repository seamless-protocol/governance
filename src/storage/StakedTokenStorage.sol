// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StakedTokenStorage {
    struct Layout {
        /// @dev Address of staking contract
        address staking;
        /// @dev Address of staking token
        address stakingToken;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.StakedToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x6393c68bbda65a43373480543c4f1ff15eb61969ce223f59d8fd1889e26cc300;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
