// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardKeeperStorage as Storage} from "../storage/RewardKeeperStorage.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";

interface IRewardKeeper {
    event ClaimedAndSetRate(address[] rewards, uint88[] rates);
    event SetRewardsController(address controller);
    event SetPool(address pool);
    event SetPeriod(uint256 period);
    event ManualWithdraw(address token, address receiver, uint256 amount);

    error ZeroAddress(address target);
    error InsufficientTimeElapsed();
    error InvalidPeriod();
    error TransferStrategyNotSet();

    /**
     * @notice Pauses the contract, disabling state-changing operations.
     * @dev Caller must have the `PAUSER_ROLE`.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract, enabling state-changing operations.
     * @dev Caller must have the `PAUSER_ROLE`.
     */
    function unpause() external;

    /**
     * @notice Claims any accrued liquidity rewards from static tokens held in transfer strategy
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param to the address of the recipient
     */
    function claimLMRewards(address to, address asset) external returns (bool);

    /**
     * @notice Claims rewards from the underlying Aave pool, sets new emission rates, and updates state.
     * @dev This operation:
     *  1) Verifies enough time has elapsed since the last claim to avoid `InsufficientTimeElapsed`.
     *  2) Calls `mintToTreasury` on the Aave Pool to collect rewards.
     *  3) Withdraws all available tokens.
     *  4) Calculates the new emission rate per second for each reward token.
     *  5) Updates emission distribution parameters and sets next distribution end.
     *  6) Emits a `ClaimedAndSetRate` event.
     * @notice Reverts if the cooldown period is not met (`InsufficientTimeElapsed`) or if the contract is paused.
     */
    function claimAndSetRate() external;

    /**
     * @notice Performs an emergency withdrawal of a specified reward token from its transfer strategy contract.
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param token The address of the reward token to withdraw.
     * @param to The recipient address for the withdrawn tokens.
     * @param amt The amount of tokens to withdraw.
     */
    function emergencyWithdrawalFromTransferStrategy(address token, address to, uint256 amt) external;
    
    /**
     * @notice Performs a manual token withdrawal
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param token The address of the token to withdraw.
     * @param to The recipient address for the withdrawn tokens.
     * @param amt The amount of tokens to withdraw.
     */
    function withdrawTokens(address token, address to, uint256 amt) external;

    /**
     * @notice Sets a new rewards controller contract.
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param controller The address of the new rewards controller.
     */
    function setRewardsController(address controller) external;

    /**
     * @notice Updates the address of the Aave Pool contract.
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param newPool The address of the new Aave Pool contract.
     */
    function setPool(address newPool) external;

    /**
     * @notice Updates the period (in seconds) used for calculating emission rates.
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param newPeriod The new period length in seconds.
     */
    function setPeriod(uint256 newPeriod) external;

    /**
     * @notice Returns the current rewards controller contract address.
     * @return The `IRewardsController` implementation currently in use.
     */
    function getController() external view returns (IRewardsController);

    /**
     * @notice Returns the current Aave Pool address used for minting/withdrawing rewards.
     * @return The `IPool` address currently in use.
     */
    function getPool() external view returns (IPool);

    /**
     * @notice Retrieves the current oracle contract used for reward configuration.
     * @return The `IEACAggregatorProxy` oracle address.
     */
    function getOracle() external view returns (IEACAggregatorProxy);

    /**
     * @notice Returns the staking token asset address.
     * @return The address of the asset used for reward distribution.
     */
    function getAsset() external view returns (address);

    /**
     * @notice Returns the length of time (in seconds) used for calculating reward emissions.
     * @return The current emission period in seconds.
     */
    function getPeriod() external view returns (uint256);

    /**
     * @notice Returns the previously used emission period (in seconds) prior to the latest update.
     * @return The previous emission period in seconds.
     */
    function getPreviousPeriod() external view returns (uint256);

    /**
     * @notice Returns the last recorded timestamp when rewards were claimed and rates were updated.
     * @return The last claim timestamp.
     */
    function getLastClaim() external view returns (uint256);

    /**
     * @notice Returns the treasury address.
     * @return treasury address.
     */
    function getTreasury() external view returns (address);
}
