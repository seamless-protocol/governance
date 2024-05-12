// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IStakedToken} from "../interfaces/IStakedToken.sol";
import {StakedTokenStorage as Storage} from "../storage/StakedTokenStorage.sol";

import "forge-std/console.sol";

contract StakedToken is IStakedToken, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public constant REWARD_PER_STAKED_TOKEN_BASE = 1e36;

    constructor() {
        _disableInitializers();
    }

    function initialize(address stakeToken, address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        Storage.Layout storage $ = Storage.layout();
        $.stakedToken = stakeToken;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override {}

    function getStakedToken() external view returns (address) {
        return Storage.layout().stakedToken;
    }

    function getTotalStaked() external view returns (uint256) {
        return Storage.layout().totalStaked;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return Storage.layout().rewardTokens;
    }

    function getRewardTokenData(address rewardToken)
        external
        view
        returns (Storage.RewardTokenData memory rewardTokenData)
    {
        return Storage.layout().rewardTokenData[rewardToken];
    }

    function getUserTotalStaked(address user) external view returns (uint256) {
        return Storage.layout().stakedBalances[user];
    }

    function getUserAccruedRewards(address user, address rewardToken) external view returns (uint256) {
        return Storage.layout().accruedRewards[user][rewardToken];
    }

    function getUserTotalRewardsForToken(address user, address rewardToken) external view returns (uint256) {
        Storage.Layout storage $ = Storage.layout();

        uint256 userStakedBalance = $.stakedBalances[user];
        uint256 rewardPerStakedToken = $.rewardTokenData[rewardToken].rewardPerStakedToken;

        Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];

        if (rewardTokenData.lastUpdatedTimestamp < block.timestamp && $.totalStaked > 0) {
            uint256 emissionPerSecond = $.emissionPerSecond[rewardToken];
            uint256 timePassed = block.timestamp - rewardTokenData.lastUpdatedTimestamp;
            uint256 tokenRewards = emissionPerSecond * timePassed;

            rewardPerStakedToken += Math.mulDiv(tokenRewards, REWARD_PER_STAKED_TOKEN_BASE, $.totalStaked);
        }

        uint256 pendingRewards = Math.mulDiv(userStakedBalance, rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);

        return $.accruedRewards[user][rewardToken] + pendingRewards - $.rewardDebt[user][rewardToken];
    }

    function addRewardTokens(address[] calldata rewardTokens, uint256[] calldata emissionPerSecond)
        external
        onlyOwner
    {
        Storage.Layout storage $ = Storage.layout();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            _updateRewards(token);

            $.emissionPerSecond[token] = emissionPerSecond[i];
            $.rewardTokens.push(token);
        }
    }

    function deposit(uint256 amount, address onBehalfOf) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage.Layout storage $ = Storage.layout();
        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            _updateRewards(rewardToken);

            Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];
            uint256 userStakedBalance = $.stakedBalances[onBehalfOf];

            if (userStakedBalance > 0) {
                uint256 accruedRewards = Math.mulDiv(
                    userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
                ) - $.rewardDebt[onBehalfOf][rewardToken];

                $.accruedRewards[onBehalfOf][rewardToken] += accruedRewards;
            }

            $.rewardDebt[onBehalfOf][rewardToken] = Math.mulDiv(
                userStakedBalance + amount, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            );
        }

        SafeERC20.safeTransferFrom(IERC20($.stakedToken), msg.sender, address(this), amount);

        $.stakedBalances[onBehalfOf] += amount;
        $.totalStaked += amount;

        emit Deposit(msg.sender, onBehalfOf, amount);
    }

    function withdraw(uint256 amount, address onBehalfOf) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage.Layout storage $ = Storage.layout();
        uint256 userStakedBalance = $.stakedBalances[msg.sender];

        if (amount > userStakedBalance) {
            revert WithdrawalExceedsBalance();
        }

        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            address rewardToken = $.rewardTokens[i];
            _updateRewards(rewardToken);

            Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];

            uint256 accruedRewards = Math.mulDiv(
                userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            ) - $.rewardDebt[msg.sender][rewardToken];

            $.accruedRewards[msg.sender][rewardToken] += accruedRewards;
            $.rewardDebt[msg.sender][rewardToken] = Math.mulDiv(
                userStakedBalance - amount, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            );
        }

        $.stakedBalances[msg.sender] -= amount;
        $.totalStaked -= amount;

        SafeERC20.safeTransfer(IERC20($.stakedToken), onBehalfOf, amount);

        emit Withdraw(msg.sender, onBehalfOf, amount);
    }

    function claimRewards(address onBehalfOf) external {
        Storage.Layout storage $ = Storage.layout();
        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            claimRewardsForToken(onBehalfOf, $.rewardTokens[i]);
        }
    }

    function claimRewardsForToken(address onBehalfOf, address rewardToken) public {
        _updateRewards(rewardToken);

        Storage.Layout storage $ = Storage.layout();
        Storage.RewardTokenData storage rewardTokenData = Storage.layout().rewardTokenData[rewardToken];

        uint256 userStakedBalance = $.stakedBalances[msg.sender];

        uint256 accruedRewards = Math.mulDiv(
            userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
        ) - $.rewardDebt[msg.sender][rewardToken];

        uint256 totalAccruedRewards = $.accruedRewards[msg.sender][rewardToken] + accruedRewards;

        $.accruedRewards[msg.sender][rewardToken] = 0;
        $.rewardDebt[msg.sender][rewardToken] =
            Math.mulDiv(userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);

        SafeERC20.safeTransfer(IERC20(rewardToken), onBehalfOf, totalAccruedRewards);

        emit ClaimRewardsForToken(msg.sender, onBehalfOf, rewardToken);
    }

    function _updateRewards(address rewardToken) internal {
        Storage.Layout storage $ = Storage.layout();
        Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];

        if (rewardTokenData.lastUpdatedTimestamp >= block.timestamp) {
            return;
        }

        if ($.totalStaked == 0) {
            rewardTokenData.lastUpdatedTimestamp = block.timestamp;
            return;
        }

        uint256 emissionPerSecond = $.emissionPerSecond[rewardToken];
        uint256 timePassed = block.timestamp - rewardTokenData.lastUpdatedTimestamp;
        uint256 tokenRewards = emissionPerSecond * timePassed;

        rewardTokenData.totalAccruedRewards += tokenRewards;
        rewardTokenData.rewardPerStakedToken += Math.mulDiv(tokenRewards, REWARD_PER_STAKED_TOKEN_BASE, $.totalStaked);
        rewardTokenData.lastUpdatedTimestamp = block.timestamp;
    }
}
