// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IAirdrop} from "./IAirdrop.sol";

/// @title Seam Airdrop Interface
/// @notice Interface for the Seam Airdrop contract
interface ISeamAirdrop is IAirdrop {
    error InvalidVestingPercentage();

    event SetVestingPercentage(uint256 vestingPercentage);
    event Transfer(address indexed recipient, uint256 seamAmount, uint256 esSeamAmount);

    /// @notice Sets the vesting percentage
    /// @param vestingPercentage Vesting percentage
    /// @dev Sets what percentage of total air-dropped SEAM tokens should be vested
    function setVestingPercentage(uint256 vestingPercentage) external;
}
