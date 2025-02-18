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

contract RewardKeeper is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, IRewardKeeper, ReentrancyGuardUpgradeable{
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
        address factory
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
        $.staticATokenFactory = IStaticATokenFactory(factory);

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
        Storage.Layout storage $ = Storage.layout();
        address asset = getAsset();
        IPool pool = getPool();
        IRewardsController controller = getController();

        address[] memory rewardTokens = pool.getReservesList();
        uint256 period = getPeriod();

        period = (((block.timestamp / period) + 1) * period) - block.timestamp;

        // check if period has elapsed, update lastClaim
        if ($.lastClaim > block.timestamp - $.previousPeriod) revert InsufficientTimeElapsed();
        $.lastClaim = block.timestamp;
        $.previousPeriod = period;

        // claim rewards
        pool.mintToTreasury(rewardTokens);

        // get new Emission rates
        uint88[] memory newRates = new uint88[](rewardTokens.length);

        // count for >0 balances
        uint256 count;
        for (uint8 i; i < rewardTokens.length; i++) {
            IERC20 token = IERC20(pool.getReserveData(rewardTokens[i]).aTokenAddress);

            uint256 balance = token.balanceOf(getTreasury());
            if (balance == 0) {
                continue;
            }

            // Transfer and deposit tokens
            // Must occur before calculating rate in order to satisfy all reward types
            StaticATokenLM staticToken =
                StaticATokenLM(getStaticATokenFactory().getStaticAToken(address(rewardTokens[i])));

            if (address(staticToken) == address(0)) {
                // if a reward token does not have a static token equivalent, we skip it.
                continue;
            }
            token.transferFrom(getTreasury(), address(this), balance);
            token.approve(address(staticToken), token.balanceOf(address(this)));
            staticToken.deposit(token.balanceOf(address(this)), address(this), 0, false);

            // there will be dust from rounding here... it can stay in the contract and get accounted for next time.
            newRates[i] = uint88(staticToken.balanceOf(address(this)) / period);

            // if rate is 0, claim amount too small. Leave in contract for next time.
            if (newRates[i] == 0) {
                continue;
            }
            count++;

            StaticATokenTransferStrategy transferStrategy =
                StaticATokenTransferStrategy(controller.getTransferStrategy(address(staticToken)));

            if (address(transferStrategy) == address(0)) {
                RewardsDataTypes.RewardsConfigInput[] memory config = new RewardsDataTypes.RewardsConfigInput[](1);
                transferStrategy =
                    new StaticATokenTransferStrategy(IERC20(address(staticToken)), address(controller), address(this));
                config[0].emissionPerSecond = 0;
                config[0].totalSupply = StaticATokenLM(address(staticToken)).totalSupply();
                config[0].distributionEnd = uint32(block.timestamp + period);
                config[0].asset = asset;
                config[0].reward = address(staticToken);
                config[0].transferStrategy = ITransferStrategyBase(address(transferStrategy));
                config[0].rewardOracle = $.oracle;
                controller.configureAssets(config);
            }

            // ensures dust is not sent.
            staticToken.transfer(address(transferStrategy), newRates[i] * period);
        }

        // Iterate through newRates to create new arrays without 0 balances
        uint88[] memory emissionRates = new uint88[](count);
        address[] memory filteredRewardTokens = new address[](count);
        IStaticATokenFactory factory = getStaticATokenFactory();
        uint256 j;
        for (uint256 k; k < newRates.length; k++) {
            if (newRates[k] > 0) {
                emissionRates[j] = newRates[k];
                filteredRewardTokens[j] = factory.getStaticAToken(rewardTokens[k]);
                j++;
            }
        }

        // set emissions per second
        controller.setEmissionPerSecond(asset, filteredRewardTokens, emissionRates);
        for (uint256 k; k < emissionRates.length; k++) {
            controller.setDistributionEnd(asset, filteredRewardTokens[k], uint32(block.timestamp + period));
        }

        emit ClaimedAndSetRate(filteredRewardTokens, emissionRates);
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

        emit TransferStrategySet(rewardToken, transferStrategy);
    }

    /// @inheritdoc IRewardKeeper
    function configureAsset(address rewardToken, uint88 rate, uint256 timespan, address transferStrategy)
        external
        override
        onlyRole(REWARD_SETTER_ROLE)
        isNotZeroAddress(rewardToken)
    {
        _checkIsManualRateAuthorized(rewardToken);

        IERC20 token = IERC20(rewardToken);
        IRewardsController controller = getController();
        uint32 deadline = uint32(block.timestamp + timespan);

        RewardsDataTypes.RewardsConfigInput[] memory config = new RewardsDataTypes.RewardsConfigInput[](1);
        config[0].emissionPerSecond = rate;
        config[0].totalSupply = IERC20(rewardToken).totalSupply();
        config[0].distributionEnd = deadline;
        config[0].asset = getAsset();
        config[0].reward = rewardToken;
        config[0].transferStrategy = ITransferStrategyBase(transferStrategy);
        config[0].rewardOracle = getOracle();
        controller.configureAssets(config);

        if (rate > 0 && rate * timespan > 0) {
            token.safeTransferFrom(msg.sender, transferStrategy, rate * timespan);
        }

        emit ConfiguredAsset(rewardToken, rate, timespan);
        emit TransferStrategySet(rewardToken, transferStrategy);
    }

    /// @inheritdoc IRewardKeeper
    function setManualRate(address rewardToken, uint88 rate)
        external
        override
        onlyRole(REWARD_SETTER_ROLE)
        isNotZeroAddress(rewardToken)
    {
        // Ensure that the given token is allowed for manual reward setting.
        _checkIsManualRateAuthorized(rewardToken);

        IRewardsController controller = getController();

        // Update the rewards controller with the new emission rate and distribution end.
        address[] memory rewardTokensArray = new address[](1);
        rewardTokensArray[0] = rewardToken;
        uint88[] memory emissionRatesArray = new uint88[](1);
        emissionRatesArray[0] = rate;
        controller.setEmissionPerSecond(getAsset(), rewardTokensArray, emissionRatesArray);

        emit ManualSetRate(rewardToken, rate);
    }

    /// @inheritdoc IRewardKeeper
    function setManualDistributionEnd(address rewardToken, uint32 deadline) external override onlyRole(REWARD_SETTER_ROLE) isNotZeroAddress(rewardToken) {
        getController().setDistributionEnd(getAsset(), rewardToken, deadline);
        emit ManualSetDistributionEnd(rewardToken, deadline);
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
        emit ManualWithdraw(token, to, amount);
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

    /// @inheritdoc IRewardKeeper
    function getController() public view override returns (IRewardsController) {
        return Storage.layout().controller;
    }

    /// @inheritdoc IRewardKeeper
    function getPool() public view override returns (IPool) {
        return Storage.layout().pool;
    }

    /// @inheritdoc IRewardKeeper
    function getOracle() public view override returns (IEACAggregatorProxy) {
        return Storage.layout().oracle;
    }

    /// @inheritdoc IRewardKeeper
    function getStaticATokenFactory() public view returns (IStaticATokenFactory) {
        return Storage.layout().staticATokenFactory;
    }

    /// @inheritdoc IRewardKeeper
    function getAsset() public view override returns (address) {
        return Storage.layout().asset;
    }

    /// @inheritdoc IRewardKeeper
    function getPeriod() public view override returns (uint256) {
        return Storage.layout().period;
    }

    /// @inheritdoc IRewardKeeper
    function getPreviousPeriod() public view override returns (uint256) {
        return Storage.layout().previousPeriod;
    }

    /// @inheritdoc IRewardKeeper
    function getLastClaim() public view override returns (uint256) {
        return Storage.layout().lastClaim;
    }

    /// @inheritdoc IRewardKeeper
    function getTreasury() public view override returns (address) {
        return Storage.layout().treasury;
    }

    /// @inheritdoc IRewardKeeper
    function getIsAllowedForManualRate(address token) public view override returns (bool) {
        return Storage.layout().allowedManualTokens[token];
    }
}
