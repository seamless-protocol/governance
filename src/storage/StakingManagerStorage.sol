// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardTokenData, RewardTokenConfig} from "../types/DataTypes.sol";

library StakingManagerStorage {
    /// @dev Data structure for token info
    struct TokenInfo {
        /// @dev Address of staked token smart contract that is ERC20 representation of position in the pool
        /// @dev Staking tokens are hold in Staking smart contract
        /// @dev StakedToken is minted when user deposits tokens and burned when user withdraws tokens, user can transfer StakedToken to other users
        /// @dev If stakedToken is not zero address this means that staking token has already been whitelisted
        address stakedToken;
        /// @dev List of reward tokens, rewards are distributed for each token in the list
        /// @dev When new reward token is added, it is appended to the list, but it is not removed when reward token is removed
        address[] rewardTokens;
        /// @dev Data for each reward token, reward per staked token and last updated timestamp
        /// @dev This data is used to calculate rewards for each user and is updated on each interaction with the contract
        /// @dev Reward token address => reward token data
        mapping(address => RewardTokenData) rewardTokenData;
        /// @dev Emission per second for each reward token
        /// @dev Reward token address => emission per second
        mapping(address => RewardTokenConfig) rewardTokenConfig;
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

    /// @dev Storage layout of the contract
    struct Layout {
        /// @dev Mapping of token info for each staking token
        mapping(address => TokenInfo) tokenInfo;
        /// @dev Array of staking tokens, used to iterate over all staking tokens
        address[] stakingTokens;
        /// @dev Address of SEAM token, contract has special logic for staking SEAM token
        address seam;
        /// @dev Address of esSEAM token, contract has special logic for esSEAM distribution
        address esSeam;
        /// @dev Address of implementation contract for StakedToken smart contract
        /// @dev When this address is changed all StakedToken contract are automatically upgraded since they are BeaconProxy
        address stakedTokenImplementation;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.StakingManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x6393c68bbda65a43373480543c4f1ff15eb61969ce223f59d8fd1889e26cc300;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
