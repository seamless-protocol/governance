// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title EscrowSeam Interface
/// @notice Interface for EscrowSeam contract.
interface IEscrowSeam is IERC20 {
    /// @notice EscrowSeam: non-transferable
    error NonTransferable();

    /// @notice Emitted when SEAM token is deposited(vested) for user.
    /// @param from Account that deposited(vested) SEAM token
    /// @param onBehalfOf Account that SEAM token is deposited(vested) for
    /// @param amount Amount of SEAM token deposited(vested)
    event Deposit(address indexed from, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when vested SEAM token is claimed for user.
    /// @param user Account that SEAM tokens are claimed for.
    /// @param amount Amount of SEAM token claimed.
    event Claim(address indexed user, uint256 amount);

    /// @notice Returns the SEAM token address.
    /// @return seamAddress SEAM token address
    function seam() external view returns (address seamAddress);

    /// @notice Returns the vesting duration.
    /// @return duration Vesting duration
    function vestingDuration() external view returns (uint256 duration);

    /// @notice Returns the vesting info for the given account.
    /// @param account Account to query
    /// @return claimableAmount Claimable amount
    /// @return vestPerSecond Amount of vested tokens per second
    /// @return vestingEndsAt Timestamp when vesting ends
    /// @return lastUpdatedTimestamp Last updated timestamp
    function vestingInfo(address account)
        external
        view
        returns (uint256 claimableAmount, uint256 vestPerSecond, uint256 vestingEndsAt, uint256 lastUpdatedTimestamp);

    /// @notice Calculates and returns total claimable(vested) amount of the account at the moment.
    /// @param account Account to query claimable amount for
    /// @return amount Claimable amount
    function getClaimableAmount(address account) external view returns (uint256 amount);

    /// @notice Vests SEAM token for user.
    /// @param onBehalfOf Account to vest SEAM token for
    /// @param amount Amount to vest
    function deposit(address onBehalfOf, uint256 amount) external;

    /// @notice Claims vested SEAM token for user.
    /// @param account Account to claim SEAM token for
    function claim(address account) external;
}
