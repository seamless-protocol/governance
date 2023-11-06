// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EscrowSeam} from "src/EscrowSeam.sol";

contract Depositor is Test {
    EscrowSeam public esSEAM;

    constructor(address _esSEAM) {
        esSEAM = EscrowSeam(_esSEAM);
    }

    function deposit(uint256 amount) external {
        esSEAM.deposit(address(this), amount);
    }

    function claim() external {
        esSEAM.claim();
    }
}
