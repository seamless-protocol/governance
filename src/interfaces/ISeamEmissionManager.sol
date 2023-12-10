// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISeamEmissionManager
/// @notice Interface for the SEAM emission manager contract.
interface ISeamEmissionManager {
    /// @notice ClaimingNotStarted: claiming cannot start yet.
    /// @param claimStartTimestamp When claiming can begin
    error ClaimingNotStarted(uint64 claimStartTimestamp);

    /// @notice Emitted when claim start timestamp is updated.
    /// @param claimStartTimestamp When claiming can begin
    event SetClaimStartTimestamp(uint256 claimStartTimestamp);

    /// @notice Emitted when emission per second is updated.
    /// @param emissionRate New emission per second
    event SetEmissionPerSecond(uint256 emissionRate);

    /// @notice Emitted when SEAM tokens are claimed.
    /// @param receiver Address that claimed SEAM tokens
    /// @param amount Amount of SEAM tokens claimed
    event Claim(address indexed receiver, uint256 amount);

    /// @notice Returns SEAM token address.
    function getSeam() external view returns (address);

    /// @notice Returns the timestamp after which claiming can start.
    function getClaimStartTimestamp() external view returns (uint64);

    /// @notice Sets emission per second.
    /// @param claimStartTimestamp When claiming can begin
    function setClaimStartTimestamp(uint64 claimStartTimestamp) external;

    /// @notice Returns last claimed timestamp.
    function getLastClaimedTimestamp() external view returns (uint64);

    /// @notice Returns emission per second.
    function getEmissionPerSecond() external view returns (uint256);

    /// @notice Sets emission per second.
    /// @dev Every time before calling this function claim function should be called to update last claimed timestamp,
    ///      otherwise new emission rate will be applied from the last claimed timestamp.
    /// @param emissionPerSecond Emission per second
    function setEmissionPerSecond(uint256 emissionPerSecond) external;

    /// @notice Claims SEAM tokens and sends them to given address.
    /// @param receiver Address to receive SEAM tokens
    function claim(address receiver) external;
}
