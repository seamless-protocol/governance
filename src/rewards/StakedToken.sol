// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IStakedToken} from "../interfaces/IStakedToken.sol";
import {StakedTokenStorage as Storage} from "../storage/StakedTokenStorage.sol";
import "forge-std/console.sol";

/// @title StakedToken contract
/// @notice Contract for staking tokens and earning multiple tokens as rewards
/// @dev For each new staking token new contract should be deployed
contract StakedToken is IStakedToken, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Constant that determines on how many decimals rewardPerStakedToken will be calculated and saved in storage
    /// @dev The more decimals this value has the more precision rewards will have
    /// @dev Nothing more that changing this value is needed in order to change precision
    uint256 public constant REWARD_PER_STAKED_TOKEN_BASE = 1e36;

    constructor() {
        _disableInitializers();
    }

    // TODO: Potentially update to BeaconProxy when final architecture is decided
    function initialize(address stakeToken, string memory name, string memory symbol, address initialOwner)
        external
        initializer
    {
        __ERC20_init_unchained(name, symbol);
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

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

    function getRewardTokenData(address rewardToken)
        external
        view
        returns (Storage.RewardTokenData memory rewardTokenData)
    {
        return Storage.layout().rewardTokenData[rewardToken];
    }

    /// @inheritdoc IStakedToken
    function getUserAccruedRewards(address user, address rewardToken) external view returns (uint256) {
        return Storage.layout().accruedRewards[user][rewardToken];
    }

    /// @inheritdoc IStakedToken
    function getUserTotalRewardsForToken(address user, address rewardToken) public view returns (uint256) {
        Storage.Layout storage $ = Storage.layout();

        uint256 totalStaked = totalSupply();
        uint256 userStakedBalance = balanceOf(user);
        uint256 rewardPerStakedToken = $.rewardTokenData[rewardToken].rewardPerStakedToken;

        Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];

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

        Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];
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

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            _updateRewards(rewardToken);

            Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];
            uint256 userStakedBalance = balanceOf(onBehalfOf);

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

            Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];

            uint256 accruedRewards = Math.mulDiv(
                userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            ) - $.rewardDebt[msg.sender][rewardToken];

            $.accruedRewards[msg.sender][rewardToken] += accruedRewards;
            $.rewardDebt[msg.sender][rewardToken] = Math.mulDiv(
                userStakedBalance - amount, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            );
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
        Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];
        uint256 userStakedBalance = balanceOf(msg.sender);

        $.rewardDebt[msg.sender][rewardToken] =
            Math.mulDiv(userStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE);
        $.accruedRewards[msg.sender][rewardToken] = 0;

        emit ClaimRewardsForToken(msg.sender, onBehalfOf, rewardToken);
    }

    function _updateRewards(address rewardToken) internal {
        Storage.Layout storage $ = Storage.layout();
        Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[rewardToken];

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

    function transfer(address to, uint256 value) public override(ERC20Upgradeable, IERC20) returns (bool) {
        Storage.Layout storage $ = Storage.layout();
        address[] memory rewardTokens = $.rewardTokens;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            console.log("1");
            _updateRewards(token);

            uint256 senderStakedBalance = balanceOf(msg.sender);
            uint256 recipientStakedBalance = balanceOf(to);

            Storage.RewardTokenData storage rewardTokenData = $.rewardTokenData[token];

            console.log("2");

            // Calculate how much rewards sender has accrued until now
            uint256 senderAccruedRewards = Math.mulDiv(
                senderStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            ) - $.rewardDebt[msg.sender][token];

            $.accruedRewards[msg.sender][token] += senderAccruedRewards;

            console.log("3");

            // Update reward debt of sender the same way as in withdraw function
            $.rewardDebt[msg.sender][token] = Math.mulDiv(
                senderStakedBalance - value, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            );

            console.log("4");

            // Calculate how much rewards recipient has accrued until now
            uint256 recipientAccruedRewards = Math.mulDiv(
                recipientStakedBalance, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            ) - $.rewardDebt[to][token];

            console.log("5");

            $.accruedRewards[to][token] += recipientAccruedRewards;

            // Update reward debt of recipient the same way as in deposit function
            $.rewardDebt[to][token] = Math.mulDiv(
                recipientStakedBalance + value, rewardTokenData.rewardPerStakedToken, REWARD_PER_STAKED_TOKEN_BASE
            );

            console.log("6");
        }

        return super.transfer(to, value);
    }
}
