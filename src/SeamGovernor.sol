// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "openzeppelin-contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
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
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {IGovernor} from "openzeppelin-contracts/governance/IGovernor.sol";
import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";
import {SeamGovernorStorage as Storage} from "./storage/SeamGovernorStorage.sol";
import {GovernorCountingFractionUpgradeable} from "./GovernorCountingFractionUpgradeable.sol";

/**
 * @title SeamGovernor
 * @author Seamless Protocol
 * @notice Governor contract of the Seamless Protocol used for both short and long governors
 */
contract SeamGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingFractionUpgradeable,
    GovernorStorageUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    error ProposalNumeratorTooLarge();

    struct InitParams {
        string name;
        uint48 initialVotingDelay;
        uint32 initialVotingPeriod;
        uint256 proposalNumeratorValue;
        uint256 voteNumeratorValue;
        uint256 quorumNumeratorValue;
        IERC5805 seam;
        IERC5805 esSEAM;
        TimelockControllerUpgradeable timelock;
        address initialOwner;
    }

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
     * @param params InitParams
     */
    function initialize(InitParams calldata params) external initializer {
        __Governor_init(params.name);
        __GovernorVotes_init(params.seam);
        __GovernorStorage_init();
        __GovernorSettings_init(params.initialVotingDelay, params.initialVotingPeriod, params.proposalNumeratorValue);
        __GovernorCountingFraction_init(params.voteNumeratorValue);
        __GovernorVotesQuorumFraction_init(params.quorumNumeratorValue);
        __GovernorTimelockControl_init(params.timelock);
        __Ownable_init(params.initialOwner);
        __UUPSUpgradeable_init();

        Storage.Layout storage $ = Storage.layout();
        $._esSEAM = params.esSEAM;
    }

    function _checkGovernance() internal override onlyOwner {}

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /// @inheritdoc GovernorSettingsUpgradeable
    function setProposalThreshold(uint256 newProposalThreshold) public override onlyGovernance {
        if (newProposalThreshold > proposalDenominator()) {
            revert ProposalNumeratorTooLarge();
        }

        _setProposalThreshold(newProposalThreshold);
    }

    /// @inheritdoc GovernorUpgradeable
    function relay(address target, uint256 value, bytes calldata data) external payable override onlyExecutor {
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        Address.verifyCallResult(success, returndata);
    }

    /**
     * @dev See {IGovernor-proposalThreshold}.
     */
    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return (token().getPastTotalSupply(clock() - 1) * super.proposalThreshold()) / proposalDenominator();
    }

    function proposalDenominator() public view virtual returns (uint256) {
        return 1000;
    }

    function _getVotes(address account, uint256 timepoint, bytes memory /*params*/ )
        internal
        view
        override(GovernorUpgradeable, GovernorVotesUpgradeable)
        returns (uint256)
    {
        return token().getPastVotes(account, timepoint) + Storage.layout()._esSEAM.getPastVotes(account, timepoint);
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
