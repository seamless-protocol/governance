// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {EscrowSeam} from "src/EscrowSeam.sol";

contract Depositor is Test {
    IERC20 public seam;
    EscrowSeam public esSEAM;

    constructor(address _SEAM, address _esSEAM) {
        seam = IERC20(_SEAM);
        esSEAM = EscrowSeam(_esSEAM);
    }

    function deposit(uint256 amount) external {
        seam.approve(address(esSEAM), amount);
        esSEAM.deposit(address(this), amount);
    }

    function claim() external {
        esSEAM.claim(address(this));
    }
}
