// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Votes} from "openzeppelin-contracts/governance/utils/Votes.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {Seam} from "src/Seam.sol";
import {SeamGovernor} from "src/SeamGovernor.sol";

contract SeamGovernorTest is Test {
    string public constant NAME = "Governor name";
    uint48 public constant VOTING_DELAY = 1234;
    uint32 public constant VOTING_PERIOD = 5678;
    uint256 public constant PROPOSAL_NUMERATOR = 10;
    uint256 public constant QUORUM_NUMERATOR = 34;
    uint256 public constant VOTE_NUMERATOR = 66;

    address immutable _seam = makeAddr("SEAM");
    address immutable _timelockController = makeAddr("timelockController");

    SeamGovernor public governorImplementation;
    SeamGovernor public governorProxy;

    function setUp() public {
        governorImplementation = new SeamGovernor();

        // 
        vm.etch(_seam, abi.encodePacked("some bytes"));
        vm.mockCall(_seam, abi.encodeWithSelector(Votes.clock.selector), abi.encode(uint48(block.timestamp)));

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(governorImplementation),
            abi.encodeWithSelector(
                SeamGovernor.initialize.selector,
                NAME,
                VOTING_DELAY,
                VOTING_PERIOD,
                PROPOSAL_NUMERATOR,
                VOTE_NUMERATOR,
                QUORUM_NUMERATOR,
                IVotes(_seam),
                TimelockControllerUpgradeable(payable(_timelockController)),
                address(this)
            )
        );
        governorProxy = SeamGovernor(payable(proxy));
    }

    function testDeployed() public {
        assertEq(governorProxy.name(), NAME);
        assertEq(governorProxy.votingDelay(), VOTING_DELAY);
        assertEq(governorProxy.votingPeriod(), VOTING_PERIOD);
        assertEq(governorProxy.proposalNumerator(), PROPOSAL_NUMERATOR);
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

    function testFuzzSetProposalNumerator(uint256 proposalNumerator) public {
        proposalNumerator = bound(proposalNumerator, 0, 1000);
        governorProxy.setProposalNumerator(proposalNumerator);
        assertEq(governorProxy.proposalNumerator(), proposalNumerator);
    }

    function testFuzzSetProposalNumeratorRevertProposalNumeratorTooLarge(uint256 proposalNumerator) public {
        proposalNumerator = bound(proposalNumerator, 1001, type(uint256).max);
        vm.expectRevert(SeamGovernor.ProposalNumeratorTooLarge.selector);
        governorProxy.setProposalNumerator(proposalNumerator);
    }

    function testFuzzUpdateQuorumNumerator(uint256 quorumNumerator) public {
        quorumNumerator = bound(quorumNumerator, 0, 100);
        governorProxy.updateQuorumNumerator(quorumNumerator);
        assertEq(governorProxy.quorumNumerator(), quorumNumerator);
    }

    function testFuzzUpdateTimelock(TimelockControllerUpgradeable timelock) public {
        governorProxy.updateTimelock(timelock);
        assertEq(governorProxy.timelock(), address(timelock));
    }

    function testProposalThreshold() public {
        uint256 totalSupply = 10 ether;
        vm.mockCall(_seam, abi.encodeWithSelector(Votes.getPastTotalSupply.selector, 1), abi.encode(totalSupply));
        governorProxy.setProposalNumerator(100); // 10%
        assertEq(governorProxy.proposalThreshold(), totalSupply / 10);
    }

    function testFuzzProposalThreshold(uint256 totalSupply, uint256 proposalThreshold) public {
        totalSupply = bound(totalSupply, 0, type(uint256).max / 1000);
        proposalThreshold = bound(proposalThreshold, 0, 1000);

        vm.mockCall(_seam, abi.encodeWithSelector(Votes.getPastTotalSupply.selector, 1), abi.encode(totalSupply));
        governorProxy.setProposalNumerator(proposalThreshold);
        assertEq(governorProxy.proposalThreshold(), (totalSupply * proposalThreshold) / 1000);
    }
}
