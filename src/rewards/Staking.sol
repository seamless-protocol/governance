// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IEscrowSeam} from "../interfaces/IEscrowSeam.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {RewardTokenData, RewardTokenConfig} from "../types/DataTypes.sol";
import {StakedToken} from "./StakedToken.sol";
import {IStakedToken} from "../interfaces/IStakedToken.sol";
import {StakedTokenBeaconProxy} from "./StakedTokenBeaconProxy.sol";
import {StakingStorage as Storage} from "../storage/StakingStorage.sol";

/// @title Staking contract
/// @notice Contract for staking tokens and earning multiple tokens as rewards
/// @dev One contract handles multiple staking tokens and multiple reward tokens for each staking token
contract Staking is IStaking, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Constant that determines on how many decimals rewardPerStakedToken will be calculated and saved in storage
    /// @dev The more decimals this value has the more precision rewards will have
    /// @dev Nothing more than changing this value is needed in order to change precision
    uint256 public constant REWARD_PER_STAKED_TOKEN_BASE = 1e36;

    modifier onlyActiveStaking(address asset) {
        if (!isStakingStarted(asset)) {
            revert StakingNotStarted();
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

    function initialize(address seam, address esSeam, address initialOwner) external initializer {
        __Ownable_init(initialOwner);

        Storage.Layout storage $ = Storage.layout();
        $.seam = seam;
        $.esSeam = esSeam;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @inheritdoc IStaking
    function getStakedTokenImplementation() external view returns (address) {
        return Storage.layout().stakedTokenImplementation;
    }

    /// @inheritdoc IStaking
    function getSeam() public view returns (address) {
        return Storage.layout().seam;
    }

    /// @inheritdoc IStaking
    function getEsSeam() public view returns (address) {
        return Storage.layout().esSeam;
    }

    /// @inheritdoc IStaking
    function getStakedToken(address stakingToken) public view returns (address) {
        return Storage.layout().tokenInfo[stakingToken].stakedToken;
    }

    /// @inheritdoc IStaking
    function isStakingStarted(address asset) public view returns (bool) {
        return Storage.layout().tokenInfo[asset].stakedToken != address(0);
    }

    /// @inheritdoc IStaking
    function getStakingTokens() external view returns (address[] memory) {
        return Storage.layout().stakingTokens;
    }

    /// @inheritdoc IStaking
    function getRewardTokens(address stakingToken) external view returns (address[] memory) {
        return Storage.layout().tokenInfo[stakingToken].rewardTokens;
    }

    /// @inheritdoc IStaking
    function getRewardTokenConfig(address stakingToken, address rewardToken)
        external
        view
        returns (RewardTokenConfig memory rewardTokenConfig)
    {
        return Storage.layout().tokenInfo[stakingToken].rewardTokenConfig[rewardToken];
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
            uint256 tokenRewards = _getTotalPendingRewards(stakingToken, rewardToken);
            rewardPerStakedToken += Math.mulDiv(tokenRewards, REWARD_PER_STAKED_TOKEN_BASE, totalStaked);
        }

        uint256 currentRewards = tokenInfo.accruedRewards[user][rewardToken];
        uint256 pendingRewards = userStakedBalance * rewardPerStakedToken;

        return
            (currentRewards + pendingRewards - tokenInfo.rewardDebt[user][rewardToken]) / REWARD_PER_STAKED_TOKEN_BASE;
    }

    /// @inheritdoc IStaking
    function setStakedTokenImplementation(address implementation) external {
        Storage.Layout storage $ = Storage.layout();
        $.stakedTokenImplementation = implementation;

        emit SetStakedTokenImplementation(implementation);
    }

    /// @inheritdoc IStaking
    function startStaking(address asset) external onlyOwner {
        Storage.Layout storage $ = Storage.layout();

        if (isStakingStarted(asset)) {
            revert StakingAlreadyStarted();
        }

        if (getStakedToken(asset) == address(0)) {
            StakedTokenBeaconProxy stakedTokenBeaconProxy = new StakedTokenBeaconProxy(
                address(this),
                abi.encodeWithSelector(StakedToken.initialize.selector, address(this), asset, "Staked Token", "STK")
            );

            $.tokenInfo[asset].stakedToken = address(stakedTokenBeaconProxy);
        }

        $.stakingTokens.push(asset);

        emit StartStaking(asset);
    }

    /// @inheritdoc IStaking
    function configureRewardToken(address stakingToken, address rewardToken, RewardTokenConfig calldata config)
        external
        onlyOwner
        onlyActiveStaking(stakingToken)
    {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        address[] storage rewardTokenList = tokenInfo.rewardTokens;

        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            if (rewardTokenList[i] == rewardToken) {
                _updateRewards(stakingToken, rewardToken);

                tokenInfo.rewardTokenConfig[rewardToken] = config;
                return;
            }
        }

        rewardTokenList.push(rewardToken);
        tokenInfo.rewardTokenConfig[rewardToken] = config;

        emit ConfigureRewardToken(
            stakingToken, rewardToken, config.startTimestamp, config.endTimestamp, config.emissionPerSecond
        );
    }

    /// @inheritdoc IStaking
    function stake(address stakingToken, uint256 amount, address recipient) external onlyActiveStaking(stakingToken) {
        // This contract will call mint on StakedToken contract
        // StakedToken contract has override for _update function which will can updateHook on this contract where logic is placed
        SafeERC20.safeTransferFrom(IERC20(stakingToken), msg.sender, address(this), amount);
        IStakedToken(getStakedToken(stakingToken)).mint(recipient, amount);

        emit Stake(stakingToken, msg.sender, recipient, amount);
    }

    /// @inheritdoc IStaking
    function unstake(address stakingToken, uint256 amount, address recipient) external {
        // This contract will call mint on StakedToken contract
        // StakedToken contract has override for _update function which will can updateHook on this contract where logic is placed
        IStakedToken(getStakedToken(stakingToken)).burn(msg.sender, amount);

        address seam = getSeam();

        if (stakingToken == seam) {
            address esSeam = getEsSeam();
            IERC20(seam).approve(esSeam, amount);
            IEscrowSeam(esSeam).deposit(recipient, amount);
        } else {
            SafeERC20.safeTransfer(IERC20(stakingToken), recipient, amount);
        }
        emit Unstake(stakingToken, msg.sender, recipient, amount);
    }

    /// @inheritdoc IStaking
    function claimRewards(address stakingToken, address recipient) external {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];

        for (uint256 i = 0; i < tokenInfo.rewardTokens.length; i++) {
            claimRewardsForToken(stakingToken, tokenInfo.rewardTokens[i], recipient);
        }
    }

    /// @inheritdoc IStaking
    function claimRewardsForToken(address stakingToken, address rewardToken, address recipient) public {
        _updateRewards(stakingToken, rewardToken);

        uint256 userTotalRewards = getUserTotalRewardsForToken(msg.sender, stakingToken, rewardToken);

        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        RewardTokenData memory rewardTokenData = tokenInfo.rewardTokenData[rewardToken];
        uint256 userStakedBalance = getUserStakedBalance(msg.sender, stakingToken);

        tokenInfo.rewardDebt[msg.sender][rewardToken] = userStakedBalance * rewardTokenData.rewardPerStakedToken;
        tokenInfo.accruedRewards[msg.sender][rewardToken] = 0;

        address esSeam = getEsSeam();
        if (rewardToken == esSeam) {
            address seam = getSeam();
            IERC20(seam).approve(esSeam, userTotalRewards);
            IEscrowSeam(esSeam).deposit(recipient, userTotalRewards);
        } else {
            SafeERC20.safeTransfer(IERC20(rewardToken), recipient, userTotalRewards);
        }

        emit ClaimRewardsForToken(msg.sender, recipient, stakingToken, rewardToken);
    }

    /// @inheritdoc IStaking
    function updateHook(address stakingToken, address sender, address recipient, uint256 value)
        external
        onlyStakedToken(stakingToken)
    {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        address[] memory rewardTokens = tokenInfo.rewardTokens;

        uint256 senderCurrentBalance = getUserStakedBalance(sender, stakingToken);
        uint256 recipientCurrentBalance = getUserStakedBalance(recipient, stakingToken);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];

            _updateRewards(stakingToken, rewardToken);

            // If sender is zero addrees, it means that this is mint operation which means that user is depositing so we don't need to update rewards for sender
            if (sender != address(0)) {
                _updateUserRewards(
                    sender, stakingToken, rewardToken, senderCurrentBalance, senderCurrentBalance - value
                );
            }

            // If recipient is zero address, it means that this is burn operation which means that user is withdrawing so we don't need to update rewards for recipient
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

        uint256 totalStaked = getTotalStaked(stakingToken);

        if (totalStaked == 0) {
            rewardTokenData.lastUpdatedTimestamp = block.timestamp;
            return;
        }

        uint256 tokenRewards = _getTotalPendingRewards(stakingToken, rewardToken);

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
            uint256 userAccruedRewards =
                userCurrentBalance * rewardTokenData.rewardPerStakedToken - tokenInfo.rewardDebt[user][rewardToken];

            tokenInfo.accruedRewards[user][rewardToken] += userAccruedRewards;
        }

        // Update reward debt of user
        tokenInfo.rewardDebt[user][rewardToken] = userFutureBalance * rewardTokenData.rewardPerStakedToken;
    }

    function _getTotalPendingRewards(address stakingToken, address rewardToken) private view returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        Storage.TokenInfo storage tokenInfo = $.tokenInfo[stakingToken];
        RewardTokenData memory rewardTokenData = tokenInfo.rewardTokenData[rewardToken];
        RewardTokenConfig memory rewardTokenConfig = tokenInfo.rewardTokenConfig[rewardToken];

        uint256 fromTimestamp = Math.max(rewardTokenConfig.startTimestamp, rewardTokenData.lastUpdatedTimestamp);
        uint256 toTimestamp = Math.min(block.timestamp, rewardTokenConfig.endTimestamp);

        if (fromTimestamp > toTimestamp) {
            return 0;
        }

        uint256 timePassed = toTimestamp - fromTimestamp;
        uint256 emissionPerSecond = rewardTokenConfig.emissionPerSecond;

        return timePassed * emissionPerSecond;
    }
}
