// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakedToken {
    // errors
    error SendFailed();
    error isZeroAddress();
    error InsufficientStake();
    error CooldownActive();
    error NotInEmergency();

    // events
    event EmergencyActive(bool status);
    event EmergencyWithdraw(address to, uint256 amt);
    event RewardsControllerChange(address RewardsController);
    event Cooldown(address user);
    event TimersUpdated(uint256 cooldown, uint256 unstake);

    function scaledTotalSupply() external view returns (uint256);

    function getScaledUserBalanceAndSupply(address user)
        external
        view
        returns (uint256, uint256);

    // Emergency functions
    function enableEmergencyWithdrawalState() external;

    function endEmergencyWithdrawalState() external;

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
    function changeController(address newController) external;

    function changeTimers(uint256 _cooldown, uint256 _unstake) external;

    // Storage getters
    function getCooldown() external view returns (uint256);

    function getUnstakeWindow() external view returns (uint256);

    function getStakerCooldown(address user) external view returns (uint256);

    function getRewardsController() external view returns (address);
}