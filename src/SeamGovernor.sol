// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "openzeppelin-contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorStorageUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import {GovernorVotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IGovernor} from "openzeppelin-contracts/governance/IGovernor.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";

/**
 * @title SeamGovernor
 * @author Seamless Protocol
 * @notice Governor contract of the Seamless Protocol used for both short and long governors
 */
contract SeamGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorStorageUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    error ProposalNumeratorTooLarge();

    modifier onlyExecutor() {
        super._checkGovernance();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes governor contract and inherited contracts.
     * @param _name Name of governor contract
     * @param _initialVotingDelay Initial voting delay
     * @param _initialVotingPeriod Initial voting period
     * @param _quorumNumeratorValue Initial quorum numerator value
     * @param _token Token used for voting
     * @param _timelock Timelock controller used for execution
     * @param initialOwner Initial owner of governor contract, should be timelock controller
     */
    function initialize(
        string memory _name,
        uint48 _initialVotingDelay,
        uint32 _initialVotingPeriod,
        uint256 _proposalNumeratorValue,
        uint256 _quorumNumeratorValue,
        IVotes _token,
        TimelockControllerUpgradeable _timelock,
        address initialOwner
    ) external initializer {
        __Governor_init(_name);
        __GovernorSettings_init(_initialVotingDelay, _initialVotingPeriod, _proposalNumeratorValue);
        __GovernorCountingSimple_init();
        __GovernorStorage_init();
        __GovernorVotes_init(_token);
        __GovernorVotesQuorumFraction_init(_quorumNumeratorValue);
        __GovernorTimelockControl_init(_timelock);
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    function _checkGovernance() internal override onlyOwner {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    function COUNTING_MODE()
        public
        pure
        override(IGovernor, GovernorCountingSimpleUpgradeable)
        returns (string memory)
    {
        return "support=bravo&quorum=for,abstain,no";
    }

    function setProposalNumerator(uint256 newProposalNumerator) external {
        setProposalThreshold(newProposalNumerator);
    }

    function setProposalThreshold(uint256 newProposalThreshold) public override onlyGovernance {
        if (newProposalThreshold > proposalDenominator()) {
            revert ProposalNumeratorTooLarge();
        }

        _setProposalThreshold(newProposalThreshold);
    }

    function updateTimelock(TimelockControllerUpgradeable newTimelock) external override onlyGovernance {
        GovernorTimelockControlStorage storage $;
        assembly {
            $.slot := 0x0d5829787b8befdbc6044ef7457d8a95c2a04bc99235349f1a212c063e59d400
        }
        emit TimelockChange(address($._timelock), address(newTimelock));
        $._timelock = newTimelock;
    }

    function relay(address target, uint256 value, bytes calldata data) external payable override onlyExecutor {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        Address.verifyCallResult(success, returndata);
    }

    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return (token().getPastTotalSupply(clock()) * proposalNumerator()) / proposalDenominator();
    }

    function proposalNumerator() public view virtual returns (uint256) {
        return super.proposalThreshold();
    }

    function proposalDenominator() public view virtual returns (uint256) {
        return 1000;
    }

    function votingDelay() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(GovernorUpgradeable, GovernorStorageUpgradeable) returns (uint256) {
        return super._propose(targets, values, calldatas, description, proposer);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }
}
