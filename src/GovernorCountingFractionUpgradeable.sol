// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {GovernorCountingSimpleUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {Checkpoints} from "openzeppelin-contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";

abstract contract GovernorCountingFractionUpgradeable is Initializable, GovernorCountingSimpleUpgradeable {
    /// @custom:storage-location erc7201:seamless.contracts.storage.GovernorCountingFraction
    struct GovernorCountingFractionStorage {
        Checkpoints.Trace208 _voteCountNumeratorHistory;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.GovernorCountingFraction")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _GOVERNOR_COUNTING_FRACTION_STORAGE_LOCATION =
        0xbb59bc16b5fc3068f9f2430313a61d2869d28b2c4b4f58bcf226eb189311be00;

    // solhint-disable-next-line var-name-mixedcase
    function _getGovernorCountingFractionStorage() private pure returns (GovernorCountingFractionStorage storage $) {
        assembly {
            $.slot := _GOVERNOR_COUNTING_FRACTION_STORAGE_LOCATION
        }
    }

    event VoteNumeratorUpdated(uint256 oldVoteNumerator, uint256 newVoteNumerator);

    /**
     * @dev The vote count set is not a valid fraction.
     */
    error GovernorInvalidVoteFraction(uint256 voteNumerator, uint256 voteDenominator);

    function _governorCountingFractionInit(uint256 voteNumeratorValue) internal onlyInitializing {
        __GovernorCountingSimple_init();
        _governorCountingFractionInitUnchained(voteNumeratorValue);
    }

    function _governorCountingFractionInitUnchained(uint256 voteNumeratorValue) internal onlyInitializing {
        _updateVoteCountNumerator(voteNumeratorValue);
    }

    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=for,abstain,no";
    }

    /**
     * @dev Returns the current quorum numerator. See {quorumDenominator}.
     */
    function voteCountNumerator() public view virtual returns (uint256) {
        // solhint-disable-next-line var-name-mixedcase
        GovernorCountingFractionStorage storage $ = _getGovernorCountingFractionStorage();
        return Checkpoints.latest($._voteCountNumeratorHistory);
    }

    /**
     * @dev Returns the quorum numerator at a specific timepoint. See {quorumDenominator}.
     */
    function voteCountNumerator(uint256 timepoint) public view virtual returns (uint256) {
        // solhint-disable-next-line var-name-mixedcase
        GovernorCountingFractionStorage storage $ = _getGovernorCountingFractionStorage();
        uint256 length = $._voteCountNumeratorHistory._checkpoints.length;

        // Optimistic search, check the latest checkpoint
        Checkpoints.Checkpoint208 storage latest = $._voteCountNumeratorHistory._checkpoints[length - 1];
        uint48 latestKey = latest._key;
        uint208 latestValue = latest._value;
        if (latestKey <= timepoint) {
            return latestValue;
        }

        // Otherwise, do the binary search
        return Checkpoints.upperLookupRecent($._voteCountNumeratorHistory, SafeCast.toUint48(timepoint));
    }

    function voteCountDenominator() public view virtual returns (uint256) {
        return 1000;
    }

    /**
     * @dev Changes the quorum numerator.
     *
     * Emits a {QuorumNumeratorUpdated} event.
     *
     * Requirements:
     *
     * - Must be called through a governance proposal.
     * - New numerator must be smaller or equal to the denominator.
     */
    function updateVoteCountNumerator(uint256 newVoteCountNumerator) external virtual onlyGovernance {
        _updateVoteCountNumerator(newVoteCountNumerator);
    }

    /**
     * @dev Changes the quorum numerator.
     *
     * Emits a {QuorumNumeratorUpdated} event.
     *
     * Requirements:
     *
     * - New numerator must be smaller or equal to the denominator.
     */
    function _updateVoteCountNumerator(uint256 newVoteCountNumerator) internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        GovernorCountingFractionStorage storage $ = _getGovernorCountingFractionStorage();
        uint256 denominator = voteCountDenominator();
        if (newVoteCountNumerator > denominator) {
            revert GovernorInvalidVoteFraction(newVoteCountNumerator, denominator);
        }

        uint256 oldVoteCountNumerator = voteCountNumerator();
        Checkpoints.push($._voteCountNumeratorHistory, clock(), SafeCast.toUint208(newVoteCountNumerator));

        emit VoteNumeratorUpdated(oldVoteCountNumerator, newVoteCountNumerator);
    }

    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalSnapshot(proposalId)) <= (againstVotes + forVotes + abstainVotes);
    }

    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        (uint256 againstVotes, uint256 forVotes,) = proposalVotes(proposalId);

        return (forVotes / (forVotes + againstVotes))
            > (voteCountNumerator(proposalSnapshot(proposalId)) / voteCountDenominator());
    }
}
