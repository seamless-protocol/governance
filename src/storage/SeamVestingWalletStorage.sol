// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

library SeamVestingWalletStorage {
    /// @custom:storage-location erc7201:seamless.contracts.storage.SeamVestingWallet
    struct Layout {
        address _beneficiary;
        IERC20 _token;
        uint256 _released;
        uint64 _start;
        uint64 _duration;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamVestingWallet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x2657d9382d871507f053a87fb7cd637b396d29844abea995422d92ff6662dd00;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
