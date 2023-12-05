// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Seam} from "src/Seam.sol";
import {SeamGovernor} from "src/SeamGovernor.sol";
import {SeamTimelockController} from "src/SeamTimelockController.sol";
import "forge-std/console.sol";

contract Proposer is Test {
    Seam public seam;
    SeamGovernor public governor;

    constructor(address seam_, address payable governor_) {
        seam = Seam(seam_);
        governor = SeamGovernor(governor_);
        seam.approve(msg.sender, type(uint256).max);
        seam.delegate(address(this));
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        vm.warp(block.timestamp + 1000);
        return governor.propose(targets, values, calldatas, description);
    }

    function queue(uint256 proposalId) public {
        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        governor.queue(proposalId);
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external {
        SeamTimelockController timelockController = SeamTimelockController(payable(governor.timelock()));
        uint256 timelockDelay = timelockController.getMinDelay();
        vm.warp(block.timestamp + timelockDelay + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }
}
