// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Seam} from "../../src/Seam.sol";

/// @notice Wrapper contract that exposes internal functions Seam
contract SeamHarness is Seam {
    function exposed_mint(address account, uint256 value) external {
        _mint(account, value);
    }
}
