// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StakedTokenStorage {
    struct RewardTokenData {
        /// @dev Reward per staked token, value is not neccessary on 18 decimals, base value is determined by REWARD_PER_STAKED_TOKEN_BASE constant
        /// @dev This value is used to calculate rewards for each user, the more decimals this value has the more precision rewards will have
        uint256 rewardPerStakedToken;
        /// @dev Last updated timestamp of rewards for this token, used to calculate accrued rewards in next interaction
        /// @dev This value can be different between reward tokens if no interaction happened after reward token is configured
        uint256 lastUpdatedTimestamp;
    }

    /// @dev Storage layout of the contract
    struct Layout {
        /// @dev Address of staking token, only one token can be staked
        address stakedToken;
        /// @dev List of reward tokens, rewards are distributed for each token in the list
        /// @dev When new reward token is added, it is appended to the list, but it is not removed when reward token is removed
        address[] rewardTokens;
        /// @dev Data for each reward token, reward per staked token and last updated timestamp
        /// @dev This data is used to calculate rewards for each user and is updated on each interaction with the contract
        /// @dev Reward token address => reward token data
        mapping(address => RewardTokenData) rewardTokenData;
        /// @dev Emission rate for each reward token, rate is in tokens per second
        /// @dev This value is used to calculate rewards for each user
        /// @dev When token is removed from rewardTokens list, emission rate is set to 0
        /// @dev Reward token address => emission rate
        mapping(address => uint256) emissionPerSecond;
        /// @dev Reward debt for each user and reward token
        /// @dev Reward debt is used when calculating rewards for user, logic is copied from MasterChef contract
        /// @dev Reward debt is calculated on each interaction with the contract
        /// @dev Account => reward token => reward debt
        mapping(address => mapping(address => uint256)) rewardDebt;
        /// @dev Accrued rewards for each user and reward token, accrued rewards are not total rewards but only rewards that user had at the time of last interaction with the contract
        /// @dev Accrued rewards are calculated on each interaction with the contract, when user claims rewards accrued rewards are set to 0
        /// @dev MasterChef contract sends rewards to user on each interaction, but this contract does not send rewards to user, user must claim rewards
        /// @dev Account => reward token => accrued rewards
        mapping(address => mapping(address => uint256)) accruedRewards;
    }

    // TODO: Update this slot and comment
    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.EscrowSeam")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x6393c68bbda65a43373480543c4f1ff15eb61969ce223f59d8fd1889e26cc300;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
