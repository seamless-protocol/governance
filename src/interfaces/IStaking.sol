// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardTokenData} from "../types/DataTypes.sol";
import {StakingStorage as Storage} from "../storage/StakingStorage.sol";

interface IStaking {
    /// @notice Error emitted when staking for token is not started
    error StakingNotStarted();

    /// @notice Error emitted when staking for token has already started
    error StakingAlreadyStarted();

    /// @notice Error emitted when someone tries to call transfer hook
    /// @dev Transfer hook should be called only by StakedToken contract
    error NotStakedToken();

    /// @notice Emitted when staking for given token is started
    /// @param asset Token that staking has started for
    event StartStaking(address indexed asset);

    /// @notice Emitted when reward token is configured for specific staking token
    /// @param stakingToken Staking token for which reward token is configured
    /// @param rewardToken Reward token that is configured
    /// @param emissionPerSecond Emission per second for given token
    event ConfigureRewardToken(address indexed stakingToken, address indexed rewardToken, uint256 emissionPerSecond);

    /// @notice Emitted when stake happens
    /// @param stakingToken Token that was staked
    /// @param from Account that staked
    /// @param recipient Account that staked for
    /// @param amount Amount staked
    event Stake(address indexed stakingToken, address indexed from, address indexed recipient, uint256 amount);

    /// @notice Emitted when withdraw happens
    /// @param stakingToken Token that was withdrawn
    /// @param from Account that withdrew
    /// @param recipient Account received the withdrawal
    /// @param amount Amount withdrawn
    event Unstake(address indexed stakingToken, address indexed from, address indexed recipient, uint256 amount);

    /// @notice Emitted when rewards are claimed for specific token
    /// @param from Account that claimed the rewards
    /// @param recipient Account that claimed the rewards for
    /// @param stakingToken Staking token for which rewards are claimed
    /// @param rewardToken Token for which rewards are claimed
    event ClaimRewardsForToken(
        address indexed from, address indexed recipient, address indexed stakingToken, address rewardToken
    );

    /// @notice Gets address of SEAM token configured for this contract
    /// @param seam Address of SEAM token
    function getSeam() external view returns (address seam);

    /// @notice Gets address of esSEAM token configured for this contract
    /// @param esSeam Address of esSEAM token
    function getEsSeam() external view returns (address esSeam);

    /// @notice Returns staked token for given staking token
    /// @param stakingToken Staking token to get staked token for
    /// @param stakedToken Staked token for given staking token
    function getStakedToken(address stakingToken) external view returns (address stakedToken);

    /// @notice Returns is staking for given token started
    /// @param asset Token to check if staking has started for
    /// @param isStarted Is staking started
    function isStakingStarted(address asset) external view returns (bool isStarted);

    /// @notice Returns list of all staking tokens
    /// @param stakingTokens List of all staking tokens
    function getStakingTokens() external view returns (address[] memory stakingTokens);

    /// @notice Returns list of reward tokens for given staking token
    /// @param stakingToken Staking token to get reward tokens for
    /// @param rewardTokens List of reward tokens
    function getRewardTokens(address stakingToken) external view returns (address[] memory rewardTokens);

    /// @notice Returns emission per second for given token
    /// @param stakingToken Staking token to get emission for
    /// @param rewardToken Reward token to get emission for
    /// @param emissionPerSecond Emission per second
    function getEmissionPerSecond(address stakingToken, address rewardToken)
        external
        view
        returns (uint256 emissionPerSecond);

    /// @notice Returns reward token data for given staking and reward token, last updated timestamp and reward per staked token
    /// @param stakingToken Staking token to get data for
    /// @param rewardToken Reward token to get data for
    /// @param rewardTokenData Data for given reward token
    function getRewardTokenData(address stakingToken, address rewardToken)
        external
        view
        returns (RewardTokenData memory rewardTokenData);

    /// @notice Returns total staked amount for given staking token
    /// @param stakingToken Staking token to get total staked amount for
    /// @param totalStaked Total staked amount for given staking token
    function getTotalStaked(address stakingToken) external view returns (uint256 totalStaked);

    /// @notice Returns total staked amount for given account and staking token
    /// @param user Account to get staked amount for
    /// @param stakingToken Staking token to get staked amount for
    /// @param stakedBalance Staked balance for given account and staking token
    function getUserStakedBalance(address user, address stakingToken) external view returns (uint256 stakedBalance);

    /// @notice Returns accrued rewards for given account, staking token and reward token
    /// @param user Account to get rewards for
    /// @param stakingToken Staking token to get rewards for
    /// @param rewardToken Reward token to get rewards for
    /// @param accruedRewards Accrued rewards for given account and reward token
    /// @dev Returned value does not represent total rewards, but only rewards that user had at the time of last user interaction with the contract
    function getUserAccruedRewardsForToken(address user, address stakingToken, address rewardToken)
        external
        view
        returns (uint256 accruedRewards);

    /// @notice Returns total rewards for given account, staking token and reward token
    /// @param user Account to get rewards for
    /// @param stakingToken Staking token to get rewards for
    /// @param rewardToken Reward token to get rewards for
    /// @param totalRewards Total rewards for given account and reward token
    /// @dev Returned value represents total rewards that user has in the moment of calling this function
    /// @dev This function is used internally to calculate rewards for user when claiming rewards and externaly to show total rewards for user
    function getUserTotalRewardsForToken(address user, address stakingToken, address rewardToken)
        external
        view
        returns (uint256 totalRewards);

    /// @notice Starts staking for given token
    /// @param asset Token to start staking for
    /// @dev This function can be called only by owner
    /// @dev If this is the first time staking is started for given token, staked token will be deployed and added to the list
    function startStaking(address asset) external;

    /// @notice Configures emission per second for given reward token for specific staking token
    /// @param stakingToken Staking token to configure emission for
    /// @param rewardToken Reward token to configure emission for
    /// @param emissionPerSecond Emission per second
    /// @dev This function can be called only by owner
    /// @dev If reward token is not in the list it will be added to the list otherwise config will be updated
    function configureRewardToken(address stakingToken, address rewardToken, uint256 emissionPerSecond) external;

    /// @notice Stakes tokens from sender on behalf of given account, given account will staked tokens
    /// @param stakingToken Staking token to stake
    /// @param amount Amount to stake
    /// @param recipient Account to stake for
    function stake(address stakingToken, uint256 amount, address recipient) external;

    /// @notice Unstakes tokens from sender on behalf of given account, given account will receive tokens
    /// @param stakingToken Staking token to unstake
    /// @param amount Amount to unstake
    /// @param recipient Account to receive tokens
    function unstake(address stakingToken, uint256 amount, address recipient) external;

    /// @notice Claims rewards for sender on given recipient account for given staking token
    /// @param stakingToken Staking token to claim rewards for
    /// @param recipient Account to receive rewards
    function claimRewards(address stakingToken, address recipient) external;

    /// @notice Claims rewards for sender on given recipient account for specific token
    /// @param stakingToken Staking token to claim rewards for
    /// @param rewardToken Token to claim rewards for
    /// @param recipient Account to receive rewards
    function claimRewardsForToken(address stakingToken, address rewardToken, address recipient) external;

    /// @notice Update hook for StakedToken smart contract
    /// @notice When user transfers, mints or burns staked tokens this hook is called and position is transfered to new owner
    /// @param stakingToken Staking token that is transfered
    /// @param sender Account that is transferring
    /// @param recipient Account that is receiving
    /// @param amount Amount that is transferred
    function updateHook(address stakingToken, address sender, address recipient, uint256 amount) external;
}
