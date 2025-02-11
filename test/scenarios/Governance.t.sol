// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {IGovernor} from "openzeppelin-contracts/governance/IGovernor.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Votes} from "openzeppelin-contracts/governance/utils/Votes.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {Seam} from "src/Seam.sol";
import {EscrowSeam} from "src/EscrowSeam.sol";
import {SeamGovernor} from "src/SeamGovernor.sol";
import {SeamTimelockController} from "src/SeamTimelockController.sol";
import {Constants} from "src/library/Constants.sol";
import {GovernorDeployer} from "script/common/GovernorDeployer.sol";
import {Proposer} from "./helpers/Proposer.sol";
import {Voter} from "./helpers/Voter.sol";

contract GovernanceTest is Test, GovernorDeployer {
    string public constant NAME = "Governor name";
    uint48 public constant VOTING_DELAY = 1234;
    uint32 public constant VOTING_PERIOD = 5678;
    uint256 public constant PROPOSAL_NUMERATOR = 10;
    uint256 public constant QUORUM_NUMERATOR = 34;

    Seam public seam;
    EscrowSeam public esSEAM;
    SeamGovernor public shortGovernor;
    SeamGovernor public longGovernor;
    SeamTimelockController public shortTimelock;
    SeamTimelockController public longTimelock;

    Proposer public shortGovernorProposer;
    Proposer public longGovernorProposer;

    Voter public shortGovernorVoter1;
    Voter public shortGovernorVoter2;
    Voter public shortGovernorVoter3;
    Voter public longGovernorVoter1;
    Voter public longGovernorVoter2;

    function setUp() public virtual {
        Seam seamTokenImplementation = new Seam();
        ERC1967Proxy seamProxy = new ERC1967Proxy(
            address(seamTokenImplementation),
            abi.encodeWithSelector(
                Seam.initialize.selector,
                Constants.TOKEN_NAME,
                Constants.TOKEN_SYMBOL,
                Constants.MINT_AMOUNT * (10 ** seamTokenImplementation.decimals())
            )
        );
        seam = Seam(address(seamProxy));

        EscrowSeam esSEAMTokenImplementation = new EscrowSeam();
        ERC1967Proxy esSEAMProxy = new ERC1967Proxy(
            address(esSEAMTokenImplementation),
            abi.encodeWithSelector(EscrowSeam.initialize.selector, address(seam), 365 days, address(this))
        );
        esSEAM = EscrowSeam(address(esSEAMProxy));

        GovernorParams memory shortGovernorParams = GovernorParams(
            Constants.GOVERNOR_SHORT_NAME,
            Constants.GOVERNOR_SHORT_VOTING_DELAY,
            Constants.GOVERNOR_SHORT_VOTING_PERIOD,
            Constants.GOVERNOR_SHORT_VOTE_NUMERATOR,
            Constants.GOVERNOR_SHORT_PROPOSAL_THRESHOLD,
            Constants.GOVERNOR_SHORT_QUORUM_NUMERATOR,
            address(seam),
            address(esSEAM),
            Constants.TIMELOCK_CONTROLLER_SHORT_MIN_DELAY,
            Constants.GUARDIAN_WALLET,
            address(this)
        );
        (shortGovernor, shortTimelock) = deployGovernorAndTimelock(shortGovernorParams);

        GovernorParams memory longGovernorParams = GovernorParams(
            Constants.GOVERNOR_LONG_NAME,
            Constants.GOVERNOR_LONG_VOTING_DELAY,
            Constants.GOVERNOR_LONG_VOTING_PERIOD,
            Constants.GOVERNOR_LONG_VOTE_NUMERATOR,
            Constants.GOVERNOR_LONG_PROPOSAL_THRESHOLD,
            Constants.GOVERNOR_LONG_QUORUM_NUMERATOR,
            address(seam),
            address(esSEAM),
            Constants.TIMELOCK_CONTROLLER_LONG_MIN_DELAY,
            Constants.GUARDIAN_WALLET,
            address(this)
        );
        (longGovernor, longTimelock) = deployGovernorAndTimelock(longGovernorParams);

        shortTimelock.grantRole(shortTimelock.DEFAULT_ADMIN_ROLE(), address(longTimelock));
        shortTimelock.revokeRole(shortTimelock.DEFAULT_ADMIN_ROLE(), address(shortTimelock));
        shortTimelock.revokeRole(shortTimelock.DEFAULT_ADMIN_ROLE(), address(this));
        longTimelock.revokeRole(longTimelock.DEFAULT_ADMIN_ROLE(), address(this));

        shortGovernor.transferOwnership(address(longTimelock));
        longGovernor.transferOwnership(address(longTimelock));

        shortGovernorProposer = new Proposer(address(seam), payable(shortGovernor));
        longGovernorProposer = new Proposer(address(seam), payable(longGovernor));
        shortGovernorVoter1 = new Voter(address(seam), payable(shortGovernor));
        shortGovernorVoter2 = new Voter(address(seam), payable(shortGovernor));
        shortGovernorVoter3 = new Voter(address(seam), payable(shortGovernor));
        longGovernorVoter1 = new Voter(address(seam), payable(longGovernor));
        longGovernorVoter2 = new Voter(address(seam), payable(longGovernor));

        seam.transfer(address(shortTimelock), 1_000_000);
        seam.transfer(address(longTimelock), 1_000_000);
        seam.transfer(address(shortGovernorProposer), 10_000_000 ether);
        seam.transfer(address(longGovernorProposer), 10_000_000 ether);
        seam.transfer(address(shortGovernorVoter1), 2_500_000 ether);
        seam.transfer(address(shortGovernorVoter2), 2_500_000 ether);
        seam.transfer(address(shortGovernorVoter3), 500_000 ether);
        seam.transfer(address(longGovernorVoter1), 2_500_000 ether);
        seam.transfer(address(longGovernorVoter2), 2_500_000 ether);
    }

    /**
     * Scenario:
     *     1. Propose grant SEAM tokens to specific address
     *     2. User1 votes for proposal
     *     3. User2 votes against proposal
     *     4. User3 votes for proposal
     *     5. Queue proposal
     *     6. Execute proposal
     */
    function test_SuccessfulProposalExecution_ShortGovernor() public {
        address receiver = makeAddr("receiver");

        address[] memory targets = new address[](1);
        targets[0] = address(seam);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IERC20.transfer.selector, address(receiver), 400_000);

        uint256 proposalId = shortGovernorProposer.propose(targets, values, calldatas, "Grant SEAM tokens");

        vm.warp(block.timestamp + Constants.GOVERNOR_SHORT_VOTING_DELAY + 1);
        shortGovernorVoter1.vote(proposalId, 1);
        shortGovernorVoter2.vote(proposalId, 0);
        shortGovernorVoter3.vote(proposalId, 1);
        shortGovernorProposer.queue(proposalId);
        shortGovernorProposer.execute(targets, values, calldatas, "Grant SEAM tokens");

        assertEq(seam.balanceOf(receiver), 400_000);
        assertEq(seam.balanceOf(address(shortTimelock)), 600_000);
    }

    // Short timelock address is changed in short governor through proposal on long governor
    function test_SuccessfulProposalExecution_LongGovernor() public {
        address newShortTimelock = makeAddr("newShortTimelock");

        address[] memory targets = new address[](1);
        targets[0] = address(shortGovernor);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] =
            abi.encodeWithSelector(GovernorTimelockControlUpgradeable.updateTimelock.selector, newShortTimelock);

        uint256 proposalId = longGovernorProposer.propose(targets, values, calldatas, "Change short timelock contract");

        vm.warp(block.timestamp + Constants.GOVERNOR_LONG_VOTING_DELAY + 1);
        longGovernorVoter1.vote(proposalId, 1);
        longGovernorVoter2.vote(proposalId, 1);
        longGovernorProposer.queue(proposalId);
        longGovernorProposer.execute(targets, values, calldatas, "Change short timelock contract");

        assertEq(address(shortGovernor.timelock()), newShortTimelock);
    }

    // Short timelock tries to update its address in short governor through proposal on short governor and fails
    function test_FailedProposalExecution_ShortGovernor() public {
        address newShortTimelock = makeAddr("newShortTimelock");

        address[] memory targets = new address[](1);
        targets[0] = address(shortGovernor);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] =
            abi.encodeWithSelector(GovernorTimelockControlUpgradeable.updateTimelock.selector, newShortTimelock);

        uint256 proposalId = shortGovernorProposer.propose(targets, values, calldatas, "Change short timelock contract");

        vm.warp(block.timestamp + Constants.GOVERNOR_SHORT_VOTING_DELAY + 1);
        shortGovernorVoter1.vote(proposalId, 1);
        shortGovernorVoter2.vote(proposalId, 1);
        shortGovernorProposer.queue(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(shortTimelock))
        );
        shortGovernorProposer.execute(targets, values, calldatas, "Change short timelock contract");
    }

    function test_GuardianStopsMaliciuosProposal() public {
        address receiver = makeAddr("receiver");

        address[] memory targets = new address[](1);
        targets[0] = address(seam);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IERC20.transfer.selector, address(receiver), 400_000);

        uint256 proposalId = shortGovernorProposer.propose(targets, values, calldatas, "Steal SEAM tokens");

        vm.warp(block.timestamp + Constants.GOVERNOR_SHORT_VOTING_DELAY + 1);
        shortGovernorVoter1.vote(proposalId, 1);
        shortGovernorVoter2.vote(proposalId, 1);
        shortGovernorProposer.queue(proposalId);

        vm.startPrank(Constants.GUARDIAN_WALLET);
        vm.warp(block.timestamp + Constants.TIMELOCK_CONTROLLER_SHORT_MIN_DELAY + 1);
        bytes32 proposalTimelockId = _hashOperationBatch(
            targets, values, calldatas, 0, bytes20(address(shortGovernor)) ^ (keccak256(bytes("Steal SEAM tokens")))
        );
        shortTimelock.cancel(proposalTimelockId);

        vm.expectRevert();
        shortGovernorProposer.execute(targets, values, calldatas, "Steal SEAM tokens");
    }

    function test_Propose_Revert_NotEnoughVotingPower() public {
        uint256 seamProposerBalance = seam.balanceOf(address(shortGovernorProposer));
        seam.transferFrom(address(shortGovernorProposer), address(this), seamProposerBalance - 200_000 ether + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector,
                address(shortGovernorProposer),
                200_000 ether - 1,
                200_000 ether
            )
        );
        shortGovernorProposer.propose(targets, values, calldatas, "Grant SEAM tokens");
    }

    function test_Queue_Revert_QuorumNotReached() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        uint256 proposalId = shortGovernorProposer.propose(targets, values, calldatas, "Grant SEAM tokens");

        vm.warp(block.timestamp + Constants.GOVERNOR_SHORT_VOTING_DELAY + 1);
        shortGovernorVoter3.vote(proposalId, 1);

        vm.expectRevert();
        shortGovernorProposer.queue(proposalId);
    }

    function test_Queue_Revert_NotEnoughVotes() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        uint256 proposalId = shortGovernorProposer.propose(targets, values, calldatas, "Grant SEAM tokens");

        vm.warp(block.timestamp + Constants.GOVERNOR_SHORT_VOTING_DELAY + 1);
        shortGovernorVoter1.vote(proposalId, 1);
        shortGovernorVoter2.vote(proposalId, 0);

        vm.expectRevert();
        shortGovernorProposer.queue(proposalId);
    }

    function test_Queue_Revert_NotEnoughVotesLong() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        uint256 proposalId = longGovernorProposer.propose(targets, values, calldatas, "Grant SEAM tokens");
        seam.transfer(address(longGovernorVoter1), 1 ether);

        vm.warp(block.timestamp + Constants.GOVERNOR_LONG_VOTING_DELAY + 1);
        longGovernorVoter1.vote(proposalId, 1);
        longGovernorVoter2.vote(proposalId, 0);

        vm.expectRevert();
        longGovernorProposer.queue(proposalId);
    }

    function testFuzz_GetVotes(uint8 fraction) public {
        vm.assume(fraction > 0);

        uint256 esSEAMAmount = seam.balanceOf(address(shortGovernorVoter1)) * fraction / type(uint8).max;

        vm.startPrank(address(shortGovernorVoter1));

        seam.approve(address(esSEAM), esSEAMAmount);
        esSEAM.deposit(address(shortGovernorVoter1), esSEAMAmount);

        // required to use constant due to bug with warp + block.timestamp: https://github.com/foundry-rs/foundry/issues/3806
        vm.warp(2);

        assertEq(shortGovernor.getVotes(address(shortGovernorVoter1), 1), seam.balanceOf(address(shortGovernorVoter1)));

        esSEAM.delegate(address(shortGovernorVoter1));

        vm.warp(3);

        assertEq(
            shortGovernor.getVotes(address(shortGovernorVoter1), 2),
            seam.balanceOf(address(shortGovernorVoter1)) + esSEAM.balanceOf(address(shortGovernorVoter1))
        );

        vm.stopPrank();
    }

    function _hashOperationBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes32 predecessor,
        bytes32 salt
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(targets, values, payloads, predecessor, salt));
    }
}
