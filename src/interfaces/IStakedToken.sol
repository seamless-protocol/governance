// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakedToken {
    /// @notice Error emitted when user tries to deposit or withdraw zero amount
    error ZeroAmount();

    /// @notice Error emitted when user tries to withdraw more than he staked
    error WithdrawalExceedsBalance();

    /// @notice Emitted when deposit happens
    /// @param from Account that deposited
    /// @param onBehalfOf Account that deposited for
    /// @param amount Amount deposited
    event Deposit(address indexed from, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when withdraw happens
    /// @param from Account that withdrew
    /// @param onBehalfOf Account received the withdrawal
    /// @param amount Amount withdrawn
    event Withdraw(address indexed from, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when rewards are claimed for specific token
    /// @param from Account that claimed the rewards
    /// @param onBehalfOf Account that claimed the rewards for
    /// @param rewardToken Token for which rewards are claimed
    event ClaimRewardsForToken(address indexed from, address indexed onBehalfOf, address indexed rewardToken);

    function deposit(uint256 amount, address onBehalfOf) external;

    function withdraw(uint256 amount, address onBehalfOf) external;

    function claimRewards(address onBehalfOf) external;
}
