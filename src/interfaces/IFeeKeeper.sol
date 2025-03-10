// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "aave-v3-periphery/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {IFeeSource} from "./IFeeSource.sol";

/**
 * @title Reward Keeper
 * @author Seamless Protocol
 * @dev A contract used to manage and accumulate reward tokens for the Seamless safety module staking system
 */
interface IFeeKeeper {
    /**
     * @notice Emitted when the rewards controller is updated
     * @param controller The address of the new rewards controller
     */
    event SetRewardsController(address controller);

    /**
     * @notice Emitted when the claim period is updated
     * @param period The new period duration in seconds
     */
    event SetPeriod(uint256 period);

    /**
     * @notice Emitted when tokens are withdrawn from the contract
     * @param token The address of the token being withdrawn
     * @param receiver The address receiving the tokens
     * @param amount The amount of tokens withdrawn
     */
    event WithdrawTokens(address indexed token, address receiver, uint256 amount);

    /**
     * @notice Emitted when a token's manual rate setting permission is updated
     * @param token The address of the token
     * @param allowed Whether manual rate setting is allowed for this token
     */
    event AllowedManualTokenUpdated(address indexed token, bool allowed);

    /**
     * @notice Emitted when a new fee source is added
     * @param feeSource The address of the fee source being added
     */
    event FeeSourceAdded(address feeSource);

    /**
     * @notice Emitted when a fee source is removed
     * @param feeSource The address of the fee source being removed
     */
    event FeeSourceRemoved(address feeSource);

    /**
     * @notice Error thrown when a zero address is provided where a valid address is required
     * @param target The zero address that was provided
     */
    error ZeroAddress(address target);

    /**
     * @notice Error thrown when attempting to claim rewards before the cooldown period has elapsed
     */
    error InsufficientTimeElapsed();

    /**
     * @notice Error thrown when an invalid period value is provided
     */
    error InvalidPeriod();

    /**
     * @notice Error thrown when a transfer strategy is not set for a token
     */
    error TransferStrategyNotSet();

    /**
     * @notice Error thrown when an unauthorized attempt is made to set a manual rate
     */
    error SetManualRateNotAuthorized();

    /**
     * @notice Error thrown when a fee source token is not unique. To distribute the same token from multiple fee sources, use a fee source that aggregates the fees from both sources
     */
    error FeeSourceTokenAlreadyExists();

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
     * @notice Claims rewards from the underlying Aave pool, sets new emission rates, and updates state.
     * Reverts if the cooldown period is not met (InsufficientTimeElapsed) or if the contract is paused.
     */
    function claimAndSetRate() external;

    /**
     * @notice Performs an emergency withdrawal of a specified reward token from its transfer strategy contract.
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param token The address of the reward token to withdraw.
     * @param to The recipient address for the withdrawn tokens.
     * @param amount The amount of tokens to withdraw.
     */
    function emergencyWithdrawalFromTransferStrategy(address token, address to, uint256 amount) external;

    /**
     * @notice Sets a transfer strategy for a given reward token.
     * @notice Should withdraw tokens from previous strategy before updating.
     * @param rewardToken address of the reward token
     * @param transferStrategy address of the new transfer strategy
     */
    function setTransferStrategy(address rewardToken, address transferStrategy) external;

    /**
     * @notice Adds a fee source to the reward keeper. Fee sources must have a unique token, i.e. you cannot have 2 fee sources for the same underlyingtoken.
     * @param feeSource address of the fee source
     */
    function addFeeSource(IFeeSource feeSource) external;

    /**
     * @notice Removes a fee source from the reward keeper.
     * @param feeSource address of the fee source
     */
    function removeFeeSource(IFeeSource feeSource) external;

    /**
     * @notice Returns all fee sources.
     * @return feeSources array of fee source addresses
     */
    function getFeeSources() external view returns (address[] memory feeSources);

    /**
     * @notice Sets whether a given token is allowed to be used with the manual reward setter.
     * @dev CAUTION: Should not be used with any fee tokens accrued by via the pool
     * @param token The underlying token address to update.
     * @param allowed True if the token should be allowed; false otherwise.
     */
    function setTokenForManualRate(address token, bool allowed) external;

    /**
     * @notice must be called for reward tokens being set for the first time
     * @dev Calls "ConfigureAsset" on the reward controller and deploys transfer strategy
     * @param rewardToken address of the reward token to add.
     * @param rate the emission rate
     * @param distributionEnd the timestamp distribution is to end at.
     * @param transferStrategy address of the transfer strategy to set.
     */
    function configureAsset(
        address rewardToken,
        uint88 rate,
        uint32 distributionEnd,
        address transferStrategy,
        address oracle
    ) external;

    /**
     * @notice Sets reward rates manually for specific tokens
     * @dev intended for use with non-static tokens
     * @dev rewardToken must be configured first
     * @param rewardTokens addresses of the reward token to add.
     * @param rates the emission rates
     */
    function setManualRate(address[] memory rewardTokens, uint88[] memory rates) external;

    /**
     * @notice Sets reward rates manually for specific tokens
     * @dev intended for use with non-static tokens
     * @dev rewardToken must be configured first
     * @param rewardToken address of the reward token to add.
     * @param deadline the amount of time for the rewards to emit
     */
    function setManualDistributionEnd(address rewardToken, uint32 deadline) external;

    /**
     * @notice Sets a claimer for a user
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param user The address of the user to set the claimer for.
     * @param caller The address of the caller to set the claimer for.
     */
    function setClaimer(address user, address caller) external;

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
     * @notice Updates the period (in seconds) used for calculating emission rates.
     * @dev Caller must have the `MANAGER_ROLE`.
     * @param newPeriod The new period length in seconds.
     */
    function setPeriod(uint256 newPeriod) external;

    /**
     * @notice Returns the current rewards controller contract address.
     * @return rewardController The `IRewardsController` implementation currently in use.
     */
    function getController() external view returns (IRewardsController rewardController);

    /**
     * @notice Retrieves the current oracle contract used for reward configuration.
     * @return oracle The `IEACAggregatorProxy` oracle address.
     */
    function getOracle() external view returns (IEACAggregatorProxy oracle);

    /**
     * @notice Returns the staking token asset address.
     * @return asset The address of the asset used for reward distribution.
     */
    function getAsset() external view returns (address asset);

    /**
     * @notice Returns the length of time (in seconds) used for calculating reward emissions.
     * @return period The current emission period in seconds.
     */
    function getPeriod() external view returns (uint256 period);

    /**
     * @notice Returns the previously used emission period (in seconds) prior to the latest update.
     * @return previousPeriod The previous emission period in seconds.
     */
    function getPreviousPeriod() external view returns (uint256 previousPeriod);

    /**
     * @notice Returns the last recorded timestamp when rewards were claimed and rates were updated.
     * @return lastClaim The last claim timestamp.
     */
    function getLastClaim() external view returns (uint256 lastClaim);

    /**
     * @notice Returns a flag indicating if a token address can have manual rate set
     * @param token address of token
     * @return isAllowed flag (bool).
     */
    function getIsAllowedForManualRate(address token) external view returns (bool isAllowed);
}
