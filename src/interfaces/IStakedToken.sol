// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";

/**
 * @title StakedToken
 * @dev A custom ERC4626 vault token with cooldown on withdrawal
 * @notice used for the Seamless Safety Module for users to generate additional yields
 */
interface IStakedToken {
    // errors
    error SendFailed();
    error ZeroAddress();
    error InsufficientStake();
    error CooldownStillActive();
    error UnstakeWindowExpired();
    error CooldownNotInitiated();
    error NotInEmergency();

    // events
    event EmergencyWithdraw(address to, uint256 amt);
    event RewardsControllerSet(address RewardsController);
    event Cooldown(address user);
    event TimersSet(uint256 cooldown, uint256 unstake);

    /**
     * @notice Returns the total supply of the staked token.
     * @notice see IScaledToken
     * @return scaledSupply The total number of tokens in circulation.
     */
    function scaledTotalSupply() external view returns (uint256 scaledSupply);

    /**
     * @notice Retrieves the scaled balance of a user and the total supply.
     * @param user The address of the user.
     * @return scaledBalance The current balance of the user.
     * @return scaledSupply The current total supply.
     */
    function getScaledUserBalanceAndSupply(address user)
        external
        view
        returns (uint256 scaledBalance, uint256 scaledSupply);

    /**
     * @notice Pauses all staking-related operations.
     * @dev Requires the caller to have the `PAUSER_ROLE`.
     */
    function pause() external;

    /**
     * @notice Unpauses the staking-related operations.
     * @dev Requires the caller to have the `PAUSER_ROLE`.
     */
    function unpause() external;

    /**
     * @notice Transfers a specified amount of underlying assets from the contract to a given address in case of emergency.
     * @dev Requires the caller to have the `MANAGER_ROLE`.
     * @param to The recipient address for the emergency withdrawal.
     * @param amt The amount of the underlying asset to withdraw.
     */
    function emergencyWithdrawal(address to, uint256 amt) external;

    /**
     * @notice Begins the cooldown period required before a user can unstake.
     * @dev The caller must have a non-zero staked balance, otherwise reverts with `InsufficientStake`.
     */
    function cooldown() external;

    /**
     * @notice Computes the next cooldown timestamp for transferring staked tokens between addresses.
     * @dev This method implements a weighted average cooldown calculation when both sender and recipient
     *      already have cooldowns.
     * @param fromCooldownTimestamp The sender's current cooldown timestamp.
     * @param amountToReceive The amount of tokens to be transferred to the recipient.
     * @param toAddress The recipient of the tokens.
     * @param toBalance The current balance of the recipient.
     * @return cooldownTimestamp The updated cooldown timestamp for the recipient.
     */
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) external view returns (uint256 cooldownTimestamp);

    /**
     * @notice Provides the number of decimal places used by the staked token.
     * @return decimal The number of decimal places.
     */
    function decimals() external view returns (uint8 decimal);

    /**
     * @notice Retrieves the current nonce for a given address.
     * @param owner The address whose nonce is being queried.
     * @return nonce The current nonce for the specified address.
     */
    function nonces(address owner) external view returns (uint256 nonce);

    /**
     * @notice Sets a new rewards controller contract.
     * @dev Requires the caller to have the `MANAGER_ROLE`.
     * @param newController The address of the new rewards controller contract.
     */
    function setController(address newController) external;

    /**
     * @notice Updates the cooldown duration and the unstake window.
     * @dev Requires the caller to have the `MANAGER_ROLE`.
     * @param _cooldown The new length (in seconds) for the cooldown period.
     * @param _unstake The new length (in seconds) for the unstake window.
     */
    function setTimers(uint256 _cooldown, uint256 _unstake) external;

    /**
     * @notice Returns the duration of the cooldown period in seconds.
     * @return cooldownTime The cooldown duration in seconds.
     */
    function getCooldown() external view returns (uint256 cooldownTime);

    /**
     * @notice Returns the duration of the unstake window in seconds.
     * @return unstakeWindow The unstake window duration in seconds.
     */
    function getUnstakeWindow() external view returns (uint256 unstakeWindow);

    /**
     * @notice Returns the stored cooldown timestamp for a given user.
     * @param user The address of the user to check.
     * @return cooldownStartedAt cooldown The cooldown timestamp for the specified user.
     */
    function getStakerCooldown(address user) external view returns (uint256 cooldownStartedAt);

    /**
     * @notice Retrieves the contract address of the current rewards controller.
     * @return rewardController The rewards controller contract.
     */
    function getRewardsController() external view returns (IRewardsController rewardController);
}
