// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Seam} from "src/Seam.sol";
import {SeamGovernor} from "src/SeamGovernor.sol";
import {Constants} from "src/library/Constants.sol";

contract Voter is Test {
    Seam public seam;
    SeamGovernor public governor;

    constructor(address seam_, address payable governor_) {
        seam = Seam(seam_);
        governor = SeamGovernor(governor_);
        seam.delegate(address(this));
    }

    function vote(uint256 proposalId, uint8 support) public {
        governor.castVote(proposalId, support);
    }
}
