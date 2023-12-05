// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {GovernorCountingSimpleUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "openzeppelin-contracts/utils/structs/Checkpoints.sol";
import {IGovernorCountingFraction} from "./interfaces/IGovernorCountingFraction.sol";
import {GovernorCountingFractionStorage as Storage} from "./storage/GovernorCountingFractionStorage.sol";

/// @title GovernorCountingFraction Contract
/// @notice Fractional counting mode for governor.
abstract contract GovernorCountingFractionUpgradeable is
    Initializable,
    IGovernorCountingFraction,
    GovernorCountingSimpleUpgradeable
{
    function __GovernorCountingFraction_init(uint256 voteNumeratorValue) internal onlyInitializing {
        __GovernorCountingSimple_init();
        __GovernorCountingFraction_init_unchained(voteNumeratorValue);
    }

    function __GovernorCountingFraction_init_unchained(uint256 voteNumeratorValue) internal onlyInitializing {
        _updateVoteCountNumerator(voteNumeratorValue);
    }

    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=for,abstain,no";
    }

    /// @inheritdoc IGovernorCountingFraction
    function voteCountNumerator() public view virtual returns (uint256) {
        return Checkpoints.latest(Storage.layout().voteCountNumeratorHistory);
    }

    /// @inheritdoc IGovernorCountingFraction
    function voteCountDenominator() public view virtual returns (uint256) {
        return 1000;
    }

    /// @inheritdoc IGovernorCountingFraction
    function voteCountNumerator(uint256 timepoint) public view virtual returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        uint256 length = $.voteCountNumeratorHistory._checkpoints.length;

        // Optimistic search, check the latest checkpoint
        Checkpoints.Checkpoint208 storage latest = $.voteCountNumeratorHistory._checkpoints[length - 1];
        uint48 latestKey = latest._key;
        uint208 latestValue = latest._value;
        if (latestKey <= timepoint) {
            return latestValue;
        }

        // Otherwise, do the binary search
        return Checkpoints.upperLookupRecent($.voteCountNumeratorHistory, SafeCast.toUint48(timepoint));
    }

    /// @inheritdoc IGovernorCountingFraction
    function updateVoteCountNumerator(uint256 newVoteCountNumerator) external virtual onlyGovernance {
        _updateVoteCountNumerator(newVoteCountNumerator);
    }

    /// @notice Updates the count numerator of the governor.
    /// @param newVoteCountNumerator New count numerator
    function _updateVoteCountNumerator(uint256 newVoteCountNumerator) internal virtual {
        Storage.Layout storage $ = Storage.layout();
        uint256 denominator = voteCountDenominator();
        if (newVoteCountNumerator > denominator) {
            revert GovernorInvalidVoteFraction(newVoteCountNumerator, denominator);
        }

        uint256 oldVoteCountNumerator = voteCountNumerator();
        Checkpoints.push($.voteCountNumeratorHistory, clock(), SafeCast.toUint208(newVoteCountNumerator));

        emit VoteNumeratorUpdated(oldVoteCountNumerator, newVoteCountNumerator);
    }

    /// @inheritdoc GovernorCountingSimpleUpgradeable
    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);

        return quorum(proposalSnapshot(proposalId)) <= (againstVotes + forVotes + abstainVotes);
    }

    /// @inheritdoc GovernorCountingSimpleUpgradeable
    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        (uint256 againstVotes, uint256 forVotes,) = proposalVotes(proposalId);

        return (forVotes * voteCountDenominator())
            > ((forVotes + againstVotes) * voteCountNumerator(proposalSnapshot(proposalId)));
    }
}
