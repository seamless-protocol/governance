// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardTokenData} from "../types/DataTypes.sol";
import {StakingStorage as Storage} from "../storage/StakingStorage.sol";

interface IStaking {
    /// @notice Error emitted when token is not supported on staking contract
    /// @dev Token must be whitelisted to be able to stake it, if user tries to deposit, withdraw or claim rewards for token that is not supported error will be emitted
    error AssetNotWhitelisted();

    /// @notice Error emitted when someone tries to call transfer hook
    /// @dev Transfer hook should be called only by StakedToken contract
    error NotStakedToken();

    /// @notice Error emitted when user tries to deposit or withdraw zero amount
    error ZeroAmount();

    /// @notice Error emitted when user tries to withdraw more than he staked
    error WithdrawalExceedsBalance();

    /// @notice Emitted when asset is whitelisted
    /// @param asset Token that was whitelisted
    event WhitelistAsset(address indexed asset);

    /// @notice Emitted when reward token is configured for specific staking token
    /// @param stakingToken Staking token for which reward token is configured
    /// @param rewardToken Reward token that is configured
    /// @param emissionPerSecond Emission per second for given token
    event ConfigureRewardToken(address indexed stakingToken, address indexed rewardToken, uint256 emissionPerSecond);

    /// @notice Emitted when deposit happens
    /// @param stakingToken Token that was deposited
    /// @param from Account that deposited
    /// @param onBehalfOf Account that deposited for
    /// @param amount Amount deposited
    event Deposit(address indexed stakingToken, address indexed from, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when withdraw happens
    /// @param stakingToken Token that was withdrawn
    /// @param from Account that withdrew
    /// @param onBehalfOf Account received the withdrawal
    /// @param amount Amount withdrawn
    event Withdraw(address indexed stakingToken, address indexed from, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when rewards are claimed for specific token
    /// @param from Account that claimed the rewards
    /// @param onBehalfOf Account that claimed the rewards for
    /// @param stakingToken Staking token for which rewards are claimed
    /// @param rewardToken Token for which rewards are claimed
    event ClaimRewardsForToken(
        address indexed from, address indexed onBehalfOf, address indexed stakingToken, address rewardToken
    );

    /// @notice Returns staked token for given staking token
    /// @param stakingToken Staking token to get staked token for
    /// @param stakedToken Staked token for given staking token
    function getStakedToken(address stakingToken) external view returns (address stakedToken);

    /// @notice Returns is given token whitelisted for staking
    /// @param asset Token to check if whitelisted
    /// @param isWhitelisted Is token whitelisted
    function isAssetWhitelisted(address asset) external view returns (bool isWhitelisted);

    /// @notice Returns list of reward tokens for given staking token
    /// @param stakingToken Staking token to get reward tokens for
    /// @param rewardTokens List of reward tokens
    function getRewardTokens(address stakingToken) external view returns (address[] memory rewardTokens);

    /// @notice Returns configured emission per second for given staking token and given reward token
    /// @param stakingToken Staking token to get emission for
    /// @param rewardToken Reward token to get emission for
    /// @param emissionPerSecond Emission per second for given token
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

    /// @notice Whitelists asset for staking
    /// @param asset Token to whitelist
    /// @dev This function can be called only by owner
    function whitelistAsset(address asset) external;

    /// @notice Configures emission per second for given reward token for given staking token
    /// @param stakingToken Staking token to configure emission for
    /// @param rewardToken Reward token to configure emission for
    /// @param emissionPerSecond Emission per second for given token
    /// @dev This function can be called only by owner
    /// @dev If reward token is not in the list it will be added to the list otherwise emission per second will be updated and reward per staked token will be recalculated
    function configureRewardToken(address stakingToken, address rewardToken, uint256 emissionPerSecond) external;

    /// @notice Stakes tokens from sender on behalf of given account, given account will staked tokens
    /// @param stakingToken Staking token to stake
    /// @param amount Amount to stake
    /// @param onBehalfOf Account to stake for
    function deposit(address stakingToken, uint256 amount, address onBehalfOf) external;

    /// @notice Withdraws tokens from sender on behalf of given account, given account will receive tokens
    /// @param stakingToken Staking token to withdraw
    /// @param amount Amount to withdraw
    /// @param onBehalfOf Account to withdraw for
    function withdraw(address stakingToken, uint256 amount, address onBehalfOf) external;

    /// @notice Claims rewards for sender on behalf of given account for given staking token
    /// @param stakingToken Staking token to claim rewards for
    /// @param onBehalfOf Account to claim rewards for
    function claimRewards(address stakingToken, address onBehalfOf) external;

    /// @notice Claims rewards for sender on behalf of given account for specific token
    /// @param stakingToken Staking token to claim rewards for
    /// @param rewardToken Token to claim rewards for
    /// @param onBehalfOf Account to claim rewards for
    function claimRewardsForToken(address stakingToken, address rewardToken, address onBehalfOf) external;

    /// @notice Update hook for StakedToken smart contract
    /// @notice When user transfers, mints or burns staked tokens this hook is called and position is transfered to new owner
    /// @param stakingToken Staking token that is transfered
    /// @param from Account that is transferring
    /// @param to Account that is receiving
    /// @param amount Amount that is transferred
    function updateHook(address stakingToken, address from, address to, uint256 amount) external;
}
