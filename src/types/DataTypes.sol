// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title DataTypes
/// @notice Data types used accross the contracts

/// @notice Data structure for reward token data
struct RewardTokenData {
    /// @dev Reward per staked token, value is not neccessary on 18 decimals, base value is determined by REWARD_PER_STAKED_TOKEN_BASE constant
    /// @dev This value is used to calculate rewards for each user, the more decimals this value has the more precision rewards will have
    uint256 rewardPerStakedToken;
    /// @dev Last updated timestamp of rewards for this token, used to calculate accrued rewards in next interaction
    /// @dev This value can be different between reward tokens if no interaction happened after reward token is configured
    uint256 lastUpdatedTimestamp;
}

struct RewardTokenConfig {
    /// @dev Start timestamp of rewards for this token, used to calculate rewards for each user
    uint256 startTimestamp;
    /// @dev End timestamp of rewards for this token, used to calculate rewards for each user
    uint256 endTimestamp;
    /// @dev Emission per second for this token, used to calculate rewards for each user
    uint256 emissionPerSecond;
}
