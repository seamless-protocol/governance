// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IStakedToken} from "../interfaces/IStakedToken.sol";
import {RewardTokenData} from "../types/DataTypes.sol";
import {StakedTokenStorage as Storage} from "../storage/StakedTokenStorage.sol";

/// @title StakedToken contract
/// @notice Contract for staking tokens and earning multiple tokens as rewards
/// @dev For each new staking token new contract should be deployed
contract StakedToken is IStakedToken, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Constant that determines on how many decimals rewardPerStakedToken will be calculated and saved in storage
    /// @dev The more decimals this value has the more precision rewards will have
    /// @dev Nothing more than changing this value is needed in order to change precision
    uint256 public constant REWARD_PER_STAKED_TOKEN_BASE = 1e36;

    constructor() {
        _disableInitializers();
    }

    // TODO: Potentially update to BeaconProxy when final architecture is decided
    function initialize(address stakeToken, string memory name, string memory symbol, address initialOwner)
        external
        initializer
    {
        __ERC20_init(name, symbol);
        __Ownable_init(initialOwner);

        Storage.Layout storage $ = Storage.layout();
        $.stakedToken = stakeToken;
    }

    // TODO: Resolve this when final architecture is decided
    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override {}

    /// @inheritdoc IStakedToken
    function getStakedToken() external view returns (address) {
        return Storage.layout().stakedToken;
    }

    /// @inheritdoc IStakedToken
    function getRewardTokens() external view returns (address[] memory) {
        return Storage.layout().rewardTokens;
    }

    /// @inheritdoc IStakedToken
    function getEmissionPerSecondForToken(address rewardToken) external view returns (uint256) {
        return Storage.layout().emissionPerSecond[rewardToken];
    }

    /// @inheritdoc IStakedToken
    function getRewardTokenData(address rewardToken) external view returns (RewardTokenData memory rewardTokenData) {
        return Storage.layout().rewardTokenData[rewardToken];
    }

    /// @inheritdoc IStakedToken
    function getUserAccruedRewards(address user, address rewardToken) external view returns (uint256) {
        return Storage.layout().accruedRewards[user][rewardToken];
    }

    /// @inheritdoc IStakedToken
    function getUserTotalRewardsForToken(address user, address rewardToken) public view returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        RewardTokenData memory rewardTokenData = $.rewardTokenData[rewardToken];

        uint256 totalStaked = totalSupply();
        uint256 userStakedBalance = balanceOf(user);
        uint256 rewardPerStakedToken = rewardTokenData.rewardPerStakedToken;

        if (rewardTokenData.lastUpdatedTimestamp < block.timestamp && totalStaked > 0) {
            uint256 emissionPerSecond = $.emissionPerSecond[rewardToken];
            uint256 timePassed = block.timestamp - rewardTokenData.lastUpdatedTimestamp;
            uint256 tokenRewards = emissionPerSecond * timePassed;

            rewardPerStakedToken += Math.mulDiv(tokenRewards, REWARD_PER_STAKED_TOKEN_BASE, totalStaked);
        }

        uint256 pendingRewards = Math.mulDiv(userStakedBalance, rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);

        return $.accruedRewards[user][rewardToken] + pendingRewards - $.rewardDebt[user][rewardToken];
    }

    /// @inheritdoc IStakedToken
    function configureRewardToken(address rewardToken, uint256 emissionPerSecond) external onlyOwner {
        Storage.Layout storage $ = Storage.layout();
        address[] storage rewardTokenList = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            if (rewardTokenList[i] == rewardToken) {
                _updateRewards(rewardToken);

                $.emissionPerSecond[rewardToken] = emissionPerSecond;
                return;
            }
        }

        rewardTokenList.push(rewardToken);

        RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];
        rewardTokenData.lastUpdatedTimestamp = block.timestamp;

        $.emissionPerSecond[rewardToken] = emissionPerSecond;
    }

    /// @inheritdoc IStakedToken
    function deposit(uint256 amount, address onBehalfOf) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage.Layout storage $ = Storage.layout();
        address[] memory rewardTokens = $.rewardTokens;
        uint256 userStakedBalance = balanceOf(onBehalfOf);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            _updateRewards(rewardToken);
            _updateUserRewards(onBehalfOf, rewardToken, userStakedBalance, userStakedBalance + amount);
        }

        SafeERC20.safeTransferFrom(IERC20($.stakedToken), msg.sender, address(this), amount);
        _mint(onBehalfOf, amount);

        emit Deposit(msg.sender, onBehalfOf, amount);
    }

    /// @inheritdoc IStakedToken
    function withdraw(uint256 amount, address onBehalfOf) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 userStakedBalance = balanceOf(msg.sender);

        if (amount > userStakedBalance) {
            revert WithdrawalExceedsBalance();
        }

        Storage.Layout storage $ = Storage.layout();

        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            address rewardToken = $.rewardTokens[i];
            _updateRewards(rewardToken);
            _updateUserRewards(msg.sender, rewardToken, userStakedBalance, userStakedBalance - amount);
        }

        _burn(msg.sender, amount);
        SafeERC20.safeTransfer(IERC20($.stakedToken), onBehalfOf, amount);

        emit Withdraw(msg.sender, onBehalfOf, amount);
    }

    /// @inheritdoc IStakedToken
    function claimRewards(address onBehalfOf) external {
        Storage.Layout storage $ = Storage.layout();
        for (uint256 i = 0; i < $.rewardTokens.length; i++) {
            claimRewardsForToken(onBehalfOf, $.rewardTokens[i]);
        }
    }

    /// @inheritdoc IStakedToken
    function claimRewardsForToken(address onBehalfOf, address rewardToken) public {
        _updateRewards(rewardToken);

        uint256 userTotalRewards = getUserTotalRewardsForToken(msg.sender, rewardToken);
        SafeERC20.safeTransfer(IERC20(rewardToken), onBehalfOf, userTotalRewards);

        Storage.Layout storage $ = Storage.layout();
        RewardTokenData memory rewardTokenData = $.rewardTokenData[rewardToken];
        uint256 userStakedBalance = balanceOf(msg.sender);

        $.rewardDebt[msg.sender][rewardToken] =
            Math.mulDiv(userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);
        $.accruedRewards[msg.sender][rewardToken] = 0;

        emit ClaimRewardsForToken(msg.sender, onBehalfOf, rewardToken);
    }

    function _updateRewards(address rewardToken) internal {
        Storage.Layout storage $ = Storage.layout();
        RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];

        if (rewardTokenData.lastUpdatedTimestamp >= block.timestamp) {
            return;
        }

        uint256 totalStaked = totalSupply();
        if (totalStaked == 0) {
            rewardTokenData.lastUpdatedTimestamp = block.timestamp;
            return;
        }

        uint256 emissionPerSecond = $.emissionPerSecond[rewardToken];
        uint256 timePassed = block.timestamp - rewardTokenData.lastUpdatedTimestamp;
        uint256 tokenRewards = emissionPerSecond * timePassed;

        rewardTokenData.rewardPerStakedToken += Math.mulDiv(tokenRewards, REWARD_PER_STAKED_TOKEN_BASE, totalStaked);
        rewardTokenData.lastUpdatedTimestamp = block.timestamp;
    }

    function transfer(address recipient, uint256 value) public override(ERC20Upgradeable, IERC20) returns (bool) {
        Storage.Layout storage $ = Storage.layout();
        address[] memory rewardTokens = $.rewardTokens;

        uint256 senderCurrentBalance = balanceOf(msg.sender);
        uint256 recipientCurrentBalance = balanceOf(recipient);
        uint256 senderFutureBalance = senderCurrentBalance - value;
        uint256 recipientFutureBalance = recipientCurrentBalance + value;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            _updateRewards(token);
            _updateUserRewards(msg.sender, token, senderCurrentBalance, senderFutureBalance);
            _updateUserRewards(recipient, token, recipientCurrentBalance, recipientFutureBalance);
        }

        return super.transfer(recipient, value);
    }

    function _updateUserRewards(
        address user,
        address rewardToken,
        uint256 userCurrentBalance,
        uint256 userFutureBalance
    ) internal {
        Storage.Layout storage $ = Storage.layout();
        RewardTokenData memory rewardTokenData = $.rewardTokenData[rewardToken];

        if (userCurrentBalance > 0) {
            // Calculate how much rewards user has accrued until now
            uint256 userAccruedRewards = Math.mulDiv(
                userCurrentBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            ) - $.rewardDebt[user][rewardToken];

            $.accruedRewards[user][rewardToken] += userAccruedRewards;
        }

        // Update reward debt of user
        $.rewardDebt[user][rewardToken] =
            Math.mulDiv(userFutureBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);
    }
}
