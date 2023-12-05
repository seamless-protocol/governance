// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title GovernorCountingFraction Interface
/// @notice Interface for GovernorCountingFraction contract.
interface IGovernorCountingFraction {
    /// @notice Invalid fractoin, maximum value is 1000.
    error GovernorInvalidVoteFraction(uint256 voteNumerator, uint256 voteDenominator);

    /// @notice Emitted when the vote numerator is updated.
    /// @param oldVoteNumerator Old vote numerator
    /// @param newVoteNumerator New vote numerator
    event VoteNumeratorUpdated(uint256 oldVoteNumerator, uint256 newVoteNumerator);

    /// @notice Returns the count numerator of the governor.
    /// @return numerator Count numerator
    function voteCountNumerator() external view returns (uint256 numerator);

    /// @notice Returns the count denominator of the governor.
    /// @return denominator Count denominator
    function voteCountDenominator() external view returns (uint256 denominator);

    /// @notice Returns the count numerator of the governor at the given timepoint.
    /// @param timepoint Timepoint to query
    /// @return numerator Count numerator
    function voteCountNumerator(uint256 timepoint) external view returns (uint256 numerator);

    /// @notice Updates the count numerator of the governor.
    /// @param newVoteCountNumerator New count numerator
    function updateVoteCountNumerator(uint256 newVoteCountNumerator) external;
}
