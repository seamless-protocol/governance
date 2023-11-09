// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title ISeamEmissionManager
/// @notice Interface for the SEAM emission manager contract.
interface ISeamEmissionManager {
    event SetEmissionPerSecond(uint256 emissionRate);
    event Claim(address indexed receiver, uint256 amount);

    /// @notice Returns SEAM token address.
    function getSeam() external view returns (address);

    /// @notice Returns last claimed timestamp.
    function getLastClaimedTimestamp() external view returns (uint256);

    /// @notice Returns emission per second.
    function getEmissionPerSecond() external view returns (uint256);

    /// @notice Sets emission per second.
    function setEmissionPerSecond(uint256) external;

    /// @notice Claims SEAM tokens and sends them to given address.
    /// @param receiver Address to receive SEAM tokens
    function claim(address receiver) external;
}
