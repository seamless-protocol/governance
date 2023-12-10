// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISeamEmissionManager
/// @notice Interface for the SEAM emission manager contract.
interface ISeamEmissionManager {
    /// @notice EmissionsNotStarted: emissions have not started, claiming cannot happen yet.
    /// @param emissionStartTimestamp When emissions begin
    error EmissionsNotStarted(uint64 emissionStartTimestamp);

    /// @notice Emitted when emission start timestamp is updated.
    /// @param emissionStartTimestamp When emissions begin
    event SetEmissionStartTimestamp(uint256 emissionStartTimestamp);

    /// @notice Emitted when emission per second is updated.
    /// @param emissionRate New emission per second
    event SetEmissionPerSecond(uint256 emissionRate);

    /// @notice Emitted when SEAM tokens are claimed.
    /// @param receiver Address that claimed SEAM tokens
    /// @param amount Amount of SEAM tokens claimed
    event Claim(address indexed receiver, uint256 amount);

    /// @notice Returns SEAM token address.
    function getSeam() external view returns (address);

    /// @notice Returns the timestamp when emissions start and claiming can begin.
    function getEmissionStartTimestamp() external view returns (uint64);

    /// @notice Sets the emissions start timestamp.
    /// @param emissionStartTimestamp When emissions should begin
    function setEmissionStartTimestamp(uint64 emissionStartTimestamp) external;

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
