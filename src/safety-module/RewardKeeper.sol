// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {ITransferStrategyBase} from "@aave/periphery-v3/contracts/rewards/interfaces/ITransferStrategyBase.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardKeeperStorage as Storage} from "../storage/RewardKeeperStorage.sol";
import {IRewardKeeper} from "../interfaces/IRewardKeeper.sol";
import {StaticATokenTransferStrategy} from "../transfer-strategies/StaticATokenTransferStrategy.sol";
import {ERC20TransferStrategy} from "../transfer-strategies/ERC20TransferStrategy.sol";
import {IStaticATokenFactory} from "static-a-token-v3/src/interfaces/IStaticATokenFactory.sol";
import {StaticATokenLM} from "static-a-token-v3/src/StaticATokenLM.sol";

contract RewardKeeper is
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    IRewardKeeper,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant REWARD_SETTER_ROLE = keccak256("REWARD_SETTER_ROLE");

    modifier isNotZeroAddress(address target) {
        if (target == address(0)) {
            revert ZeroAddress(target);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    function initialize(
        address pool,
        address initialAdmin,
        address stkSeam,
        address oracle,
        address treasury,
        address staticATokenfactory
    ) external initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        Storage.Layout storage $ = Storage.layout();

        $.pool = IPool(pool);
        $.oracle = IEACAggregatorProxy(oracle);
        $.period = 1 days;
        $.lastClaim = block.timestamp;
        $.asset = stkSeam;
        $.treasury = treasury;
        $.staticATokenFactory = IStaticATokenFactory(staticATokenfactory);

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// @inheritdoc IRewardKeeper
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IRewardKeeper
    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IRewardKeeper
    function claimLMRewards(address to, address asset, address[] calldata rewards)
        external
        override
        isNotZeroAddress(to)
        onlyRole(MANAGER_ROLE)
    {
        IRewardsController controller = getController();

        address staticAToken = getStaticATokenFactory().getStaticAToken(asset);
        StaticATokenTransferStrategy transferStrategy =
            StaticATokenTransferStrategy(controller.getTransferStrategy(staticAToken));
        if (address(transferStrategy) == address(0)) {
            revert TransferStrategyNotSet();
        }
        transferStrategy.claimRewards(to, rewards);
    }

    /// @inheritdoc IRewardKeeper
    function claimAndSetRate() external override whenNotPaused nonReentrant {
        address asset = getAsset();
        IPool pool = getPool();
        IRewardsController controller = getController();
        IEACAggregatorProxy oracle = getOracle();
        address[] memory rewardTokens = pool.getReservesList();
        uint256 period = _validateAndUpdatePeriod();

        // used for setting emissions
        uint88[] memory emissionRates = new uint88[](1);
        address[] memory staticTokens = new address[](1);

        // claim rewards
        pool.mintToTreasury(rewardTokens);
        for (uint8 i; i < rewardTokens.length; i++) {
            IERC20 token = IERC20(pool.getReserveData(rewardTokens[i]).aTokenAddress);
            uint256 balance = token.balanceOf(getTreasury());

            staticTokens[0] = getStaticATokenFactory().getStaticAToken(address(rewardTokens[i]));
            address transferStrategy = controller.getTransferStrategy(staticTokens[0]);

            if (staticTokens[0] == address(0) || balance == 0) {
                continue;
            }

            emissionRates[0] = _processAToken(token, staticTokens[0], balance, period);

            if (emissionRates[0] == 0) {
                continue;
            }

            if (transferStrategy == address(0)) {
                transferStrategy = address(
                    new StaticATokenTransferStrategy(IERC20(staticTokens[0]), address(controller), address(this))
                );
                _configureAssets(
                    staticTokens[0], transferStrategy, oracle, asset, controller, 0, uint32(block.timestamp)
                );
            }

            controller.setEmissionPerSecond(asset, staticTokens, emissionRates);
            controller.setDistributionEnd(asset, staticTokens[0], uint32(block.timestamp + period));
            IERC20(staticTokens[0]).transfer(address(transferStrategy), emissionRates[0] * period);

            emit SetRate(staticTokens, emissionRates);
            emit SetDistributionEnd(staticTokens[0], uint32(block.timestamp + period));
        }
    }

    /// @inheritdoc IRewardKeeper
    function setTokenForManualRate(address token, bool allowed)
        external
        override
        onlyRole(MANAGER_ROLE)
        isNotZeroAddress(token)
    {
        Storage.layout().allowedManualTokens[token] = allowed;
        emit AllowedManualTokenUpdated(token, allowed);
    }

    /// @inheritdoc IRewardKeeper
    function setTransferStrategy(address rewardToken, address transferStrategy)
        external
        override
        onlyRole(REWARD_SETTER_ROLE)
        isNotZeroAddress(rewardToken)
    {
        getController().setTransferStrategy(rewardToken, ITransferStrategyBase(transferStrategy));

        emit SetTransferStrategy(rewardToken, transferStrategy);
    }

    /// @inheritdoc IRewardKeeper
    function configureAsset(
        address rewardToken,
        uint88 rate,
        uint32 distributionEnd,
        address transferStrategy,
        address oracle
    ) external override onlyRole(REWARD_SETTER_ROLE) isNotZeroAddress(rewardToken) {
        _checkIsManualRateAuthorized(rewardToken);
        _configureAssets(
            rewardToken,
            transferStrategy,
            IEACAggregatorProxy(oracle),
            getAsset(),
            getController(),
            rate,
            distributionEnd
        );

        emit ConfiguredAsset(rewardToken, rate, distributionEnd);
    }

    /// @inheritdoc IRewardKeeper
    function setManualRate(address[] memory rewardTokens, uint88[] memory rates)
        external
        override
        onlyRole(REWARD_SETTER_ROLE)
    {
        // Ensure that the given token is allowed for manual reward setting.
        for (uint256 i; i < rewardTokens.length; i++) {
            _checkIsManualRateAuthorized(rewardTokens[i]);
        }
        getController().setEmissionPerSecond(getAsset(), rewardTokens, rates);

        emit SetRate(rewardTokens, rates);
    }

    /// @inheritdoc IRewardKeeper
    function setManualDistributionEnd(address rewardToken, uint32 deadline)
        external
        override
        onlyRole(REWARD_SETTER_ROLE)
        isNotZeroAddress(rewardToken)
    {
        getController().setDistributionEnd(getAsset(), rewardToken, deadline);
        emit SetDistributionEnd(rewardToken, deadline);
    }

    /// @inheritdoc IRewardKeeper
    function emergencyWithdrawalFromTransferStrategy(address token, address to, uint256 amount)
        external
        override
        isNotZeroAddress(to)
        isNotZeroAddress(token)
        onlyRole(MANAGER_ROLE)
    {
        address transferStrategy = getController().getTransferStrategy(token);
        if (transferStrategy == address(0)) revert TransferStrategyNotSet();
        ITransferStrategyBase(transferStrategy).emergencyWithdrawal(token, to, amount);
    }

    /// @inheritdoc IRewardKeeper
    function withdrawTokens(address token, address to, uint256 amount) external override onlyRole(MANAGER_ROLE) {
        IERC20(token).safeTransfer(to, amount);
        emit WithdrawTokens(token, to, amount);
    }

    /// @inheritdoc IRewardKeeper
    function setRewardsController(address controller)
        external
        override
        isNotZeroAddress(controller)
        onlyRole(MANAGER_ROLE)
    {
        Storage.layout().controller = IRewardsController(controller);
        emit SetRewardsController(controller);
    }

    /// @inheritdoc IRewardKeeper
    function setPool(address newPool) external override isNotZeroAddress(newPool) onlyRole(MANAGER_ROLE) {
        Storage.layout().pool = IPool(newPool);
        emit SetPool(newPool);
    }

    /// @inheritdoc IRewardKeeper
    function setPeriod(uint256 newPeriod) external override onlyRole(MANAGER_ROLE) {
        if (newPeriod == 0) revert InvalidPeriod();
        Storage.layout().period = newPeriod;
        emit SetPeriod(newPeriod);
    }

    /**
     * @notice handles validation and updates of periods
     */
    function _validateAndUpdatePeriod() internal returns (uint256 newPeriod) {
        // check if period has elapsed, update lastClaim
        if (getLastClaim() > block.timestamp - getPreviousPeriod()) revert InsufficientTimeElapsed();
        uint256 period = getPeriod();
        newPeriod = (((block.timestamp / period) + 1) * period) - block.timestamp;
        Storage.layout().lastClaim = block.timestamp;
        Storage.layout().previousPeriod = newPeriod;
    }

    /**
     * @notice transfers aToken from treasury and then wraps into static token
     * @dev also calculates and returns the rate
     * @param aToken interface of the aToken
     * @param staticToken the address of the static token
     * @param balance the balance of aToken
     * @param period the period for the current cycle
     */
    function _processAToken(IERC20 aToken, address staticToken, uint256 balance, uint256 period)
        internal
        returns (uint88 rate)
    {
        aToken.transferFrom(getTreasury(), address(this), balance);
        aToken.approve(staticToken, aToken.balanceOf(address(this)));
        StaticATokenLM(staticToken).deposit(aToken.balanceOf(address(this)), address(this), 0, false);
        rate = uint88(IERC20(staticToken).balanceOf(address(this)) / period);
    }

    /**
     * @notice Calls configureAssets on the rewards controller
     * @param rewardToken the address of the reward token
     * @param transferStrategy the address of the corresponding transfer strategy
     * @param oracle the interface for the oracle contract
     * @param asset the address of the asset (stkSEAM)
     * @param controller the interface for the rewards controller
     * @param rate the emission rate
     * @param distributionEnd the timestamp to end distribution
     */
    function _configureAssets(
        address rewardToken,
        address transferStrategy,
        IEACAggregatorProxy oracle,
        address asset,
        IRewardsController controller,
        uint88 rate,
        uint32 distributionEnd
    ) internal {
        RewardsDataTypes.RewardsConfigInput[] memory config = new RewardsDataTypes.RewardsConfigInput[](1);
        config[0].emissionPerSecond = rate;
        config[0].totalSupply = 0;
        config[0].distributionEnd = distributionEnd;
        config[0].asset = asset;
        config[0].reward = rewardToken;
        config[0].transferStrategy = ITransferStrategyBase(address(transferStrategy));
        config[0].rewardOracle = oracle;
        controller.configureAssets(config);
    }

    /**
     * @notice Checks if the incoming address has been approved for manual rate
     * @param rewardToken address of the reward token
     */
    function _checkIsManualRateAuthorized(address rewardToken) internal view {
        if (!getIsAllowedForManualRate(rewardToken)) {
            revert SetManualRateNotAuthorized();
        }
    }

    /// @inheritdoc IRewardKeeper
    function getController() public view override returns (IRewardsController rewardController) {
        rewardController = Storage.layout().controller;
    }

    /// @inheritdoc IRewardKeeper
    function getPool() public view override returns (IPool pool) {
        pool = Storage.layout().pool;
    }

    /// @inheritdoc IRewardKeeper
    function getOracle() public view override returns (IEACAggregatorProxy oracle) {
        oracle = Storage.layout().oracle;
    }

    /// @inheritdoc IRewardKeeper
    function getStaticATokenFactory() public view returns (IStaticATokenFactory staticATokenFactory) {
        staticATokenFactory = Storage.layout().staticATokenFactory;
    }

    /// @inheritdoc IRewardKeeper
    function getAsset() public view override returns (address asset) {
        asset = Storage.layout().asset;
    }

    /// @inheritdoc IRewardKeeper
    function getPeriod() public view override returns (uint256 period) {
        period = Storage.layout().period;
    }

    /// @inheritdoc IRewardKeeper
    function getPreviousPeriod() public view override returns (uint256 previousPeriod) {
        previousPeriod = Storage.layout().previousPeriod;
    }

    /// @inheritdoc IRewardKeeper
    function getLastClaim() public view override returns (uint256 lastClaim) {
        lastClaim = Storage.layout().lastClaim;
    }

    /// @inheritdoc IRewardKeeper
    function getTreasury() public view override returns (address treasury) {
        treasury = Storage.layout().treasury;
    }

    /// @inheritdoc IRewardKeeper
    function getIsAllowedForManualRate(address token) public view override returns (bool isAllowed) {
        isAllowed = Storage.layout().allowedManualTokens[token];
    }
}
