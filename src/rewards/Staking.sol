// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {RewardTokenData} from "../types/DataTypes.sol";
import {StakedToken} from "./StakedToken.sol";
import {IStakedToken} from "../interfaces/IStakedToken.sol";
import {StakingStorage as Storage} from "../storage/StakingStorage.sol";

import "forge-std/console.sol";

/// @title Staking contract
/// @notice Contract for staking tokens and earning multiple tokens as rewards
/// @dev One contract handles multiple staking tokens and multiple reward tokens for each staking token
contract Staking is IStaking, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Constant that determines on how many decimals rewardPerStakedToken will be calculated and saved in storage
    /// @dev The more decimals this value has the more precision rewards will have
    /// @dev Nothing more than changing this value is needed in order to change precision
    uint256 public constant REWARD_PER_STAKED_TOKEN_BASE = 1e36;

    modifier onlyWhitelistedAsset(address asset) {
        if (!isAssetWhitelisted(asset)) {
            revert AssetNotWhitelisted();
        }
        _;
    }

    modifier onlyStakedToken(address stakingToken) {
        if (msg.sender != getStakedToken(stakingToken)) {
            revert NotStakedToken();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @inheritdoc IStaking
    function getStakedToken(address stakingToken) public view returns (address) {
        return Storage.layout().tokenInfo[stakingToken].stakedToken;
    }

    /// @inheritdoc IStaking
    function isAssetWhitelisted(address asset) public view returns (bool) {
        return Storage.layout().isAssetWhitelisted[asset];
    }

    /// @inheritdoc IStaking
    function getRewardTokens(address stakingToken) external view returns (address[] memory) {
        return Storage.layout().tokenInfo[stakingToken].rewardTokens;
    }

    /// @inheritdoc IStaking
    function getEmissionPerSecond(address stakingToken, address rewardToken) external view returns (uint256) {
        return Storage.layout().tokenInfo[stakingToken].emissionPerSecond[rewardToken];
    }

    /// @inheritdoc IStaking
    function getRewardTokenData(address stakingToken, address rewardToken)
        external
        view
        returns (RewardTokenData memory rewardTokenData)
    {
        return Storage.layout().tokenInfo[stakingToken].rewardTokenData[rewardToken];
    }

    /// @inheritdoc IStaking
    function getTotalStaked(address stakingToken) public view returns (uint256) {
        return IERC20(Storage.layout().tokenInfo[stakingToken].stakedToken).totalSupply();
    }

    /// @inheritdoc IStaking
    function getUserStakedBalance(address user, address stakingToken) public view returns (uint256) {
        return IERC20(Storage.layout().tokenInfo[stakingToken].stakedToken).balanceOf(user);
    }

    /// @inheritdoc IStaking
    function getUserAccruedRewardsForToken(address user, address stakingToken, address rewardToken)
        external
        view
        returns (uint256)
    {
        return Storage.layout().tokenInfo[stakingToken].accruedRewards[user][rewardToken];
    }

    /// @inheritdoc IStaking
    function getUserTotalRewardsForToken(address user, address stakingToken, address rewardToken)
        public
        view
        returns (uint256)
    {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        RewardTokenData memory rewardTokenData = tokenInfo.rewardTokenData[rewardToken];

        uint256 totalStaked = getTotalStaked(stakingToken);
        uint256 userStakedBalance = getUserStakedBalance(user, stakingToken);
        uint256 rewardPerStakedToken = rewardTokenData.rewardPerStakedToken;

        if (rewardTokenData.lastUpdatedTimestamp < block.timestamp && totalStaked > 0) {
            uint256 emissionPerSecond = tokenInfo.emissionPerSecond[rewardToken];
            uint256 timePassed = block.timestamp - rewardTokenData.lastUpdatedTimestamp;
            uint256 tokenRewards = emissionPerSecond * timePassed;

            rewardPerStakedToken += Math.mulDiv(tokenRewards, REWARD_PER_STAKED_TOKEN_BASE, totalStaked);
        }

        uint256 pendingRewards = Math.mulDiv(userStakedBalance, rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);

        return tokenInfo.accruedRewards[user][rewardToken] + pendingRewards - tokenInfo.rewardDebt[user][rewardToken];
    }

    /// @inheritdoc IStaking
    function whitelistAsset(address asset) external onlyOwner {
        Storage.Layout storage $ = Storage.layout();

        $.isAssetWhitelisted[asset] = true;
        $.stakingTokens.push(asset);

        // TODO: Beacon Proxy
        address stakedToken = address(new StakedToken(address(this), asset, address(this), "Ime", "symbol"));
        $.tokenInfo[asset].stakedToken = stakedToken;

        emit WhitelistAsset(asset);
    }

    /// @inheritdoc IStaking
    function configureRewardToken(address stakingToken, address rewardToken, uint256 emissionPerSecond)
        external
        onlyOwner
    {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        address[] storage rewardTokenList = tokenInfo.rewardTokens;

        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            if (rewardTokenList[i] == rewardToken) {
                _updateRewards(stakingToken, rewardToken);

                tokenInfo.emissionPerSecond[rewardToken] = emissionPerSecond;
                return;
            }
        }

        rewardTokenList.push(rewardToken);

        RewardTokenData storage rewardTokenData = tokenInfo.rewardTokenData[rewardToken];
        rewardTokenData.lastUpdatedTimestamp = block.timestamp;

        tokenInfo.emissionPerSecond[rewardToken] = emissionPerSecond;

        emit ConfigureRewardToken(stakingToken, rewardToken, emissionPerSecond);
    }

    /// @inheritdoc IStaking
    function deposit(address stakingToken, uint256 amount, address onBehalfOf)
        external
        onlyWhitelistedAsset(stakingToken)
    {
        // Storage.Layout storage $ = Storage.layout();
        // Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];

        // address[] memory rewardTokens = tokenInfo.rewardTokens;
        // uint256 userStakedBalance = getUserStakedBalance(onBehalfOf, stakingToken);

        // for (uint256 i = 0; i < rewardTokens.length; i++) {
        //     address rewardToken = rewardTokens[i];
        //     _updateRewards(stakingToken, rewardToken);
        //     _updateUserRewards(onBehalfOf, stakingToken, rewardToken, userStakedBalance, userStakedBalance + amount);
        // }

        // TODO: Rethink to send tokens to staked token

        IStakedToken(getStakedToken(stakingToken)).mint(onBehalfOf, amount);
        SafeERC20.safeTransferFrom(IERC20(stakingToken), msg.sender, address(this), amount);

        emit Deposit(stakingToken, msg.sender, onBehalfOf, amount);
    }

    /// @inheritdoc IStaking
    function withdraw(address stakingToken, uint256 amount, address onBehalfOf)
        external
        onlyWhitelistedAsset(stakingToken)
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // uint256 userStakedBalance = getUserStakedBalance(msg.sender, stakingToken);

        // if (amount > userStakedBalance) {
        //     revert WithdrawalExceedsBalance();
        // }

        // Storage.Layout storage $ = Storage.layout();
        // Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];

        // for (uint256 i = 0; i < tokenInfo.rewardTokens.length; i++) {
        //     address rewardToken = tokenInfo.rewardTokens[i];
        //     _updateRewards(stakingToken, rewardToken);
        //     _updateUserRewards(msg.sender, stakingToken, rewardToken, userStakedBalance, userStakedBalance - amount);
        // }

        // TODO: rethink also this
        IStakedToken(getStakedToken(stakingToken)).burn(msg.sender, amount);
        SafeERC20.safeTransfer(IERC20(stakingToken), onBehalfOf, amount);

        emit Withdraw(stakingToken, msg.sender, onBehalfOf, amount);
    }

    /// @inheritdoc IStaking
    function claimRewards(address stakingToken, address onBehalfOf) external onlyWhitelistedAsset(stakingToken) {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];

        for (uint256 i = 0; i < tokenInfo.rewardTokens.length; i++) {
            claimRewardsForToken(stakingToken, tokenInfo.rewardTokens[i], onBehalfOf);
        }
    }

    /// @inheritdoc IStaking
    function claimRewardsForToken(address stakingToken, address rewardToken, address onBehalfOf)
        public
        onlyWhitelistedAsset(stakingToken)
    {
        _updateRewards(stakingToken, rewardToken);

        uint256 userTotalRewards = getUserTotalRewardsForToken(msg.sender, stakingToken, rewardToken);
        SafeERC20.safeTransfer(IERC20(rewardToken), onBehalfOf, userTotalRewards);

        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        RewardTokenData memory rewardTokenData = tokenInfo.rewardTokenData[rewardToken];
        uint256 userStakedBalance = getUserStakedBalance(msg.sender, stakingToken);

        tokenInfo.rewardDebt[msg.sender][rewardToken] =
            Math.mulDiv(userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);
        tokenInfo.accruedRewards[msg.sender][rewardToken] = 0;

        emit ClaimRewardsForToken(msg.sender, onBehalfOf, stakingToken, rewardToken);
    }

    /// @inheritdoc IStaking
    function updateHook(address stakingToken, address sender, address recipient, uint256 value)
        external
        onlyStakedToken(stakingToken)
    {
        if (value == 0) {
            revert ZeroAmount();
        }

        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        address[] memory rewardTokens = tokenInfo.rewardTokens;

        uint256 senderCurrentBalance = getUserStakedBalance(sender, stakingToken);
        uint256 recipientCurrentBalance = getUserStakedBalance(recipient, stakingToken);

        if (senderCurrentBalance < value && sender != address(0)) {
            revert WithdrawalExceedsBalance();
        }

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];

            _updateRewards(stakingToken, rewardToken);

            if (sender != address(0)) {
                _updateUserRewards(
                    sender, stakingToken, rewardToken, senderCurrentBalance, senderCurrentBalance - value
                );
            }

            if (recipient != address(0)) {
                _updateUserRewards(
                    recipient, stakingToken, rewardToken, recipientCurrentBalance, recipientCurrentBalance + value
                );
            }
        }
    }

    function _updateRewards(address stakingToken, address rewardToken) internal {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        RewardTokenData storage rewardTokenData = tokenInfo.rewardTokenData[rewardToken];

        if (rewardTokenData.lastUpdatedTimestamp >= block.timestamp) {
            return;
        }

        uint256 totalStaked = getTotalStaked(stakingToken);

        if (totalStaked == 0) {
            rewardTokenData.lastUpdatedTimestamp = block.timestamp;
            return;
        }

        uint256 emissionPerSecond = tokenInfo.emissionPerSecond[rewardToken];
        uint256 timePassed = block.timestamp - rewardTokenData.lastUpdatedTimestamp;
        uint256 tokenRewards = emissionPerSecond * timePassed;

        rewardTokenData.rewardPerStakedToken += Math.mulDiv(tokenRewards, REWARD_PER_STAKED_TOKEN_BASE, totalStaked);
        rewardTokenData.lastUpdatedTimestamp = block.timestamp;
    }

    function _updateUserRewards(
        address user,
        address stakingToken,
        address rewardToken,
        uint256 userCurrentBalance,
        uint256 userFutureBalance
    ) internal {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        RewardTokenData memory rewardTokenData = tokenInfo.rewardTokenData[rewardToken];

        if (userCurrentBalance > 0) {
            // Calculate how much rewards user has accrued until now
            uint256 userAccruedRewards = Math.mulDiv(
                userCurrentBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            ) - tokenInfo.rewardDebt[user][rewardToken];

            tokenInfo.accruedRewards[user][rewardToken] += userAccruedRewards;
        }

        // Update reward debt of user
        tokenInfo.rewardDebt[user][rewardToken] =
            Math.mulDiv(userFutureBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);
    }
}
