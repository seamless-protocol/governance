// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    function scaledTotalSupply() external view returns (uint256);

    function getScaledUserBalanceAndSupply(address user)
        external
        view
        returns (uint256, uint256);

    // Emergency functions
    function pause() external;

    function unpause() external;

    function emergencyWithdrawal(address to, uint256 amt) external;
    function cooldown() external;
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) external view returns (uint256);

    function decimals() external view returns (uint8);

    function nonces(address owner)
        external
        view
        returns (uint256);

    // Admin Functions
    function setController(address newController) external;

    function setTimers(uint256 _cooldown, uint256 _unstake) external;

    // Storage getters
    function getCooldown() external view returns (uint256);

    function getUnstakeWindow() external view returns (uint256);

    function getStakerCooldown(address user) external view returns (uint256);

    function getRewardsController() external view returns (address);
}