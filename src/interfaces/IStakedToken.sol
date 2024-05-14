// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IStakedToken is IERC20 {
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

    /// @notice Returns address of staking token
    function getStakedToken() external view returns (address);

    /// @notice Returns list of reward tokens
    function getRewardTokens() external view returns (address[] memory);

    /// @notice Returns accrued rewards for given account and reward token
    /// @param user Account to get rewards for
    /// @param rewardToken Token to get rewards for
    /// @dev Returned value does not represent total rewards, but only rewards that user had at the time of last user interaction with the contract
    function getUserAccruedRewards(address user, address rewardToken) external view returns (uint256);

    /// @notice Returns total rewards for given account and reward token
    /// @param user Account to get rewards for
    /// @param rewardToken Token to get rewards for
    /// @dev Returned value represents total rewards that user has in the moment of calling this function
    /// @dev This function is used internally to calculate rewards for user when claiming rewards and externaly to show total rewards for user
    function getUserTotalRewardsForToken(address user, address rewardToken) external view returns (uint256);

    /// @notice Configures emission per second for given reward token
    /// @param rewardToken Token to configure emission for
    /// @param emissionPerSecond Emission per second for given token
    /// @dev This function can be called only by owner
    /// @dev If reward token is not in the list it will be added to the list otherwise emission per second will be updated and reward per staked token will be recalculated
    function configureRewardToken(address rewardToken, uint256 emissionPerSecond) external;

    /// @notice Stakes tokens from sender on behalf of given account, given account will staked tokens
    /// @param amount Amount to stake
    /// @param onBehalfOf Account to stake for
    function deposit(uint256 amount, address onBehalfOf) external;

    /// @notice Withdraws tokens from sender on behalf of given account, given account will receive tokens
    /// @param amount Amount to withdraw
    /// @param onBehalfOf Account to withdraw for
    function withdraw(uint256 amount, address onBehalfOf) external;

    /// @notice Claims rewards for sender on behalf of given account
    /// @param onBehalfOf Account to claim rewards for
    function claimRewards(address onBehalfOf) external;

    /// @notice Claims rewards for sender on behalf of given account for specific token
    /// @param rewardToken Token to claim rewards for
    /// @param onBehalfOf Account to claim rewards for
    function claimRewardsForToken(address rewardToken, address onBehalfOf) external;
}
