// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Votes} from "openzeppelin-contracts/governance/utils/Votes.sol";
import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {Seam} from "src/Seam.sol";
import {SeamGovernor} from "src/SeamGovernor.sol";

contract SeamGovernorTest is Test {
    string public constant NAME = "Governor name";
    uint48 public constant VOTING_DELAY = 1234;
    uint32 public constant VOTING_PERIOD = 5678;
    uint256 public constant PROPOSAL_THRESHOLD = 10;
    uint256 public constant QUORUM_NUMERATOR = 34;
    uint256 public constant VOTE_NUMERATOR = 666;

    address immutable _seam = makeAddr("SEAM");
    address immutable _esSEAM = makeAddr("esSEAM");
    address immutable _timelockController = makeAddr("timelockController");

    SeamGovernor public governorImplementation;
    SeamGovernor public governorProxy;

    function setUp() public {
        governorImplementation = new SeamGovernor();

        vm.etch(_seam, abi.encodePacked("some bytes"));
        vm.mockCall(_seam, abi.encodeWithSelector(Votes.clock.selector), abi.encode(uint48(block.timestamp)));

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(governorImplementation),
            abi.encodeWithSelector(
                SeamGovernor.initialize.selector,
                SeamGovernor.InitParams({
                    name: NAME,
                    initialVotingDelay: VOTING_DELAY,
                    initialVotingPeriod: VOTING_PERIOD,
                    proposalThresholdValue: PROPOSAL_THRESHOLD,
                    voteNumeratorValue: VOTE_NUMERATOR,
                    quorumNumeratorValue: QUORUM_NUMERATOR,
                    seam: IERC5805(_seam),
                    esSEAM: IERC5805(_esSEAM),
                    timelock: TimelockControllerUpgradeable(
                        payable(_timelockController)
                    ),
                    initialOwner: address(this)
                })
            )
        );
        governorProxy = SeamGovernor(payable(proxy));
    }

    function testDeployed() public {
        assertEq(governorProxy.name(), NAME);
        assertEq(governorProxy.votingDelay(), VOTING_DELAY);
        assertEq(governorProxy.votingPeriod(), VOTING_PERIOD);
        assertEq(governorProxy.quorumNumerator(), QUORUM_NUMERATOR);
        assertEq(address(governorProxy.token()), _seam);
        assertEq(address(governorProxy.timelock()), _timelockController);
        assertEq(governorProxy.owner(), address(this));
    }

    function testUpgrade() public {
        address newImplementation = address(new SeamGovernor());
        governorProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        address nonOwner = makeAddr("nonOwner");
        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        governorProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        vm.stopPrank();
    }

    function testFuzzSetVotingDelay(uint48 votingDelay) public {
        governorProxy.setVotingDelay(votingDelay);
        assertEq(governorProxy.votingDelay(), votingDelay);
    }

    function testFuzzSetVotingDelayRevertNotOwner(address caller) public {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        governorProxy.setVotingDelay(1);
        vm.stopPrank();
    }

    function testFuzzSetVotingPeriod(uint32 votingPeriod) public {
        vm.assume(votingPeriod > 0);
        governorProxy.setVotingPeriod(votingPeriod);
        assertEq(governorProxy.votingPeriod(), votingPeriod);
    }

    function testFuzzUpdateQuorumNumerator(uint256 quorumNumerator) public {
        quorumNumerator = bound(quorumNumerator, 0, 100);
        governorProxy.updateQuorumNumerator(quorumNumerator);
        assertEq(governorProxy.quorumNumerator(), quorumNumerator);
    }

    function testFuzzUpdateVoteCountNumerator(uint256 voteCountNumerator) public {
        voteCountNumerator = bound(voteCountNumerator, 0, 100);
        governorProxy.updateVoteCountNumerator(voteCountNumerator);
        assertEq(governorProxy.voteCountNumerator(), voteCountNumerator);
    }

    function testFuzzUpdateTimelock(TimelockControllerUpgradeable timelock) public {
        governorProxy.updateTimelock(timelock);
        assertEq(governorProxy.timelock(), address(timelock));
    }

    function testProposalThreshold() public {
        governorProxy.setProposalThreshold(100);
        assertEq(governorProxy.proposalThreshold(), 100);
    }

    function testFuzzProposalThreshold(uint256 proposalThreshold) public {
        governorProxy.setProposalThreshold(proposalThreshold);
        assertEq(governorProxy.proposalThreshold(), proposalThreshold);
    }
}
