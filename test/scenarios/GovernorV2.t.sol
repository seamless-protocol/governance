// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamGovernorV2} from "../../src/SeamGovernorV2.sol";
import {Constants} from "../../src/library/Constants.sol";
import {GovernanceTest} from "./Governance.t.sol";
import {StakedToken} from "../../src/StakedToken.sol";

contract GovernorV2Test is GovernanceTest {
    StakedToken stkSEAM;

    function setUp() public override {
        super.setUp();

        stkSEAM = _deployStakedSEAM();

        SeamGovernorV2 seamGovernorV2 = new SeamGovernorV2();

        vm.startPrank(address(longTimelock));
        shortGovernor.upgradeToAndCall(
            address(seamGovernorV2), abi.encodeWithSelector(SeamGovernorV2.initializeV2.selector, stkSEAM)
        );

        longGovernor.upgradeToAndCall(
            address(seamGovernorV2), abi.encodeWithSelector(SeamGovernorV2.initializeV2.selector, stkSEAM)
        );

        vm.stopPrank();
    }

    function test_TokensArray() public view {
        IERC5805[] memory shortTokens = SeamGovernorV2(payable(address(shortGovernor))).tokens();
        IERC5805[] memory longTokens = SeamGovernorV2(payable(address(longGovernor))).tokens();

        assertEq(shortTokens.length, 3);
        assertEq(longTokens.length, 3);

        assertEq(address(shortTokens[0]), address(seam));
        assertEq(address(shortTokens[1]), address(esSEAM));
        assertEq(address(shortTokens[2]), address(stkSEAM));

        assertEq(address(longTokens[0]), address(seam));
        assertEq(address(longTokens[1]), address(esSEAM));
        assertEq(address(longTokens[2]), address(stkSEAM));
    }

    function test_GetVotes(uint256 seamAmount, uint256 esSEAMAmount, uint256 stkSEAMAmount) public {
        seamAmount = bound(seamAmount, 0, 1_000_000 ether);
        esSEAMAmount = bound(esSEAMAmount, 0, seamAmount);
        stkSEAMAmount = bound(stkSEAMAmount, 0, seamAmount - esSEAMAmount);

        address voter = makeAddr("voter");

        // Setup SEAM balance and delegation
        seam.transfer(voter, seamAmount);

        vm.startPrank(voter);
        seam.delegate(voter);

        // Setup esSEAM balance and delegation
        seam.approve(address(esSEAM), esSEAMAmount);
        esSEAM.deposit(voter, esSEAMAmount);
        esSEAM.delegate(voter);

        // Setup stkSEAM balance and delegation
        seam.approve(address(stkSEAM), stkSEAMAmount);
        stkSEAM.deposit(stkSEAMAmount, voter);
        stkSEAM.delegate(voter);
        vm.stopPrank();

        // Move forward one block to activate delegations
        vm.warp(block.timestamp + 1);

        uint256 expectedVotes = seamAmount;

        assertEq(
            SeamGovernorV2(payable(address(shortGovernor))).getVotes(voter, block.timestamp - 1),
            expectedVotes,
            "Short governor votes mismatch"
        );

        assertEq(
            SeamGovernorV2(payable(address(longGovernor))).getVotes(voter, block.timestamp - 1),
            expectedVotes,
            "Long governor votes mismatch"
        );
    }

    function test_ProposalWithStkSEAMVotes() public {
        // Setup voter with stkSEAM voting power
        address proposer = makeAddr("proposer");
        uint256 stakeAmount = 200_000 ether;

        seam.transfer(proposer, stakeAmount);
        vm.startPrank(proposer);
        seam.approve(address(stkSEAM), stakeAmount);
        stkSEAM.deposit(stakeAmount, proposer);
        stkSEAM.delegate(proposer);

        // Create proposal
        address receiver = makeAddr("receiver");
        address[] memory targets = new address[](1);
        targets[0] = address(seam);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IERC20.transfer.selector, receiver, 100);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = shortGovernor.propose(targets, values, calldatas, "Test proposal");
        vm.stopPrank();

        // Vote and execute
        vm.warp(block.timestamp + Constants.GOVERNOR_SHORT_VOTING_DELAY + 1);
        vm.prank(address(shortGovernorVoter1));
        SeamGovernorV2(payable(address(shortGovernor))).castVote(proposalId, 1);

        vm.warp(block.timestamp + Constants.GOVERNOR_SHORT_VOTING_PERIOD + 1);

        shortGovernor.queue(proposalId);
        vm.warp(block.timestamp + Constants.TIMELOCK_CONTROLLER_SHORT_MIN_DELAY + 1);
        shortGovernor.execute(proposalId);

        assertEq(seam.balanceOf(receiver), 100);
    }

    function _deployStakedSEAM() internal returns (StakedToken) {
        StakedToken implementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                address(seam),
                address(this),
                "TEST", // "stakedSEAM",
                "TST", // "stkSEAM",
                7 days,
                1 days
            )
        );

        return StakedToken(address(proxy));
    }
}
