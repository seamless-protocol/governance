// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Transfer strategy Interface
/// @notice Interface for the transfer strategy contract
/// @dev This interface should be implemented by all transfer strategy contracts
interface ITransferStrategyBase {
    /// @notice Only incentives controller can perform transfer
    error NotIncentivesController();

    /// @notice Only rewards admin can emergency withdraw
    error NotRewardsAdmin();

    /// @notice Emitted when emergency withdrawal is called by rewards admin
    /// @param caller Address of the caller
    /// @param token Address of the token to withdraw funds from this contract
    /// @param to Address of the recipient of the withdrawal
    /// @param amount Amount to withdraw
    event EmergencyWithdrawal(address indexed caller, address indexed token, address indexed to, uint256 amount);

    /// @notice Perform custom transfer logic via delegate call from source contract to a TransferStrategy implementation
    /// @param to Account to transfer rewards
    /// @param reward Address of the reward token
    /// @param amount Amount to transfer to the "to" address parameter
    /// @return success true bool if transfer logic succeeds
    function performTransfer(address to, address reward, uint256 amount) external returns (bool success);

    /// @notice Returns the address of the Incentives Controller
    function getIncentivesController() external view returns (address);

    /// @notice Returns the address of the Rewards admin
    function getRewardsAdmin() external view returns (address);

    /// @notice Perform an emergency token withdrawal only callable by the Rewards admin
    /// @param token Address of the token to withdraw funds from this contract
    /// @param to Address of the recipient of the withdrawal
    /// @param amount Amount of the withdrawal
    function emergencyWithdrawal(address token, address to, uint256 amount) external;
}
