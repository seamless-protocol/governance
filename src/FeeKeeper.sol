// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {ITransferStrategyBase} from "aave-v3-periphery/contracts/rewards/interfaces/ITransferStrategyBase.sol";
import {IEACAggregatorProxy} from "aave-v3-periphery/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {RewardsDataTypes} from "aave-v3-periphery/contracts/rewards/libraries/RewardsDataTypes.sol";
import {FeeKeeperStorage} from "./storage/FeeKeeperStorage.sol";
import {IFeeKeeper} from "./interfaces/IFeeKeeper.sol";
import {ERC20TransferStrategy} from "./transfer-strategies/ERC20TransferStrategy.sol";
import {IFeeSource} from "./interfaces/IFeeSource.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

/**
 * @title FeeKeeper
 * @author Seamless Protocol
 * @notice Contract that manages fee collection and distribution to stakers
 * @dev This contract collects fees from various sources and distributes them as rewards
 *      to stakers through the Rewards Controller. It supports multiple fee sources
 *      and reward tokens, and allows for manual rate setting for authorized tokens.
 *      The contract is upgradeable, access-controlled, and pausable.
 */
contract FeeKeeper is
    IFeeKeeper,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    FeeKeeperStorage
{
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant REWARD_SETTER_ROLE = keccak256("REWARD_SETTER_ROLE");

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
    function initialize(address initialAdmin, address asset, address oracle) external initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        StorageLayout storage $ = storageLayout();

        $.oracle = IEACAggregatorProxy(oracle);
        $.period = 1 days;
        $.lastClaim = block.timestamp;
        $.asset = asset;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
        _grantRole(REWARD_SETTER_ROLE, initialAdmin);
        _grantRole(UPGRADER_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// @inheritdoc IFeeKeeper
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IFeeKeeper
    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IFeeKeeper
    function claimAndSetRate() external override whenNotPaused nonReentrant {
        address asset = getAsset();
        IRewardsController controller = getController();
        IEACAggregatorProxy oracle = getOracle();
        uint256 period = _validateAndUpdatePeriod();

        uint88[] memory emissionRates = new uint88[](1);
        address[] memory rewardTokens = new address[](1);

        address[] memory feeSources = getFeeSources();

        for (uint256 i; i < feeSources.length; i++) {
            IFeeSource feeSource = IFeeSource(feeSources[i]);
            IERC20 token = feeSource.token();

            // claim fees
            feeSource.claim();

            uint256 balance = token.balanceOf(address(this));

            if (balance == 0) {
                continue;
            }

            emissionRates[0] = uint88(balance / period);

            if (emissionRates[0] == 0) {
                continue;
            }

            address transferStrategy = controller.getTransferStrategy(address(token));

            if (transferStrategy == address(0)) {
                transferStrategy = address(new ERC20TransferStrategy(token, address(controller), address(this)));
                _configureAssets(
                    address(token),
                    transferStrategy,
                    oracle,
                    asset,
                    controller,
                    emissionRates[0],
                    uint32(block.timestamp + period)
                );
            } else {
                rewardTokens[0] = address(token);
                controller.setEmissionPerSecond(asset, rewardTokens, emissionRates);
                controller.setDistributionEnd(asset, address(token), uint32(block.timestamp + period));
            }

            SafeERC20.safeTransfer(IERC20(token), address(transferStrategy), emissionRates[0] * period);
        }
    }

    /// @inheritdoc IFeeKeeper
    function addFeeSource(IFeeSource feeSource)
        external
        override
        onlyRole(MANAGER_ROLE)
        isNotZeroAddress(address(feeSource))
    {
        _checkFeeSourceTokenIsUnique(feeSource);

        storageLayout().feeSources.add(address(feeSource));

        emit FeeSourceAdded(address(feeSource));
    }

    /// @inheritdoc IFeeKeeper
    function removeFeeSource(IFeeSource feeSource)
        external
        override
        onlyRole(MANAGER_ROLE)
        isNotZeroAddress(address(feeSource))
    {
        storageLayout().feeSources.remove(address(feeSource));
        emit FeeSourceRemoved(address(feeSource));
    }

    /// @inheritdoc IFeeKeeper
    function getFeeSources() public view override returns (address[] memory feeSources) {
        feeSources = storageLayout().feeSources.values();
    }

    /// @inheritdoc IFeeKeeper
    function setTokenForManualRate(address token, bool allowed)
        external
        override
        onlyRole(MANAGER_ROLE)
        isNotZeroAddress(token)
    {
        storageLayout().allowedManualTokens[token] = allowed;
        emit AllowedManualTokenUpdated(token, allowed);
    }

    /// @inheritdoc IFeeKeeper
    function setTransferStrategy(address rewardToken, address transferStrategy)
        external
        override
        onlyRole(REWARD_SETTER_ROLE)
        isNotZeroAddress(rewardToken)
    {
        _checkIsManualRateAuthorized(rewardToken);
        getController().setTransferStrategy(rewardToken, ITransferStrategyBase(transferStrategy));
    }

    /// @inheritdoc IFeeKeeper
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
    }

    /// @inheritdoc IFeeKeeper
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
    }

    /// @inheritdoc IFeeKeeper
    function setManualDistributionEnd(address rewardToken, uint32 deadline)
        external
        override
        onlyRole(REWARD_SETTER_ROLE)
        isNotZeroAddress(rewardToken)
    {
        getController().setDistributionEnd(getAsset(), rewardToken, deadline);
    }

    /// @inheritdoc IFeeKeeper
    function setClaimer(address user, address caller) external override onlyRole(MANAGER_ROLE) {
        getController().setClaimer(user, caller);
    }

    /// @inheritdoc IFeeKeeper
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

    /// @inheritdoc IFeeKeeper
    function withdrawTokens(address token, address to, uint256 amount) external override onlyRole(MANAGER_ROLE) {
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        emit WithdrawTokens(token, to, amount);
    }

    /// @inheritdoc IFeeKeeper
    function setRewardsController(address controller)
        external
        override
        isNotZeroAddress(controller)
        onlyRole(MANAGER_ROLE)
    {
        storageLayout().controller = IRewardsController(controller);
        emit SetRewardsController(controller);
    }

    /// @inheritdoc IFeeKeeper
    function setPeriod(uint256 newPeriod) external override onlyRole(MANAGER_ROLE) {
        if (newPeriod == 0) revert InvalidPeriod();
        storageLayout().period = newPeriod;
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
        storageLayout().lastClaim = block.timestamp;
        storageLayout().previousPeriod = newPeriod;
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

    function _checkFeeSourceTokenIsUnique(IFeeSource feeSource) internal view {
        address[] memory feeSources = getFeeSources();

        for (uint256 i; i < feeSources.length; i++) {
            if (address(IFeeSource(feeSources[i]).token()) == address(feeSource.token())) {
                revert FeeSourceTokenAlreadyExists();
            }
        }
    }

    /// @inheritdoc IFeeKeeper
    function getController() public view override returns (IRewardsController rewardController) {
        rewardController = storageLayout().controller;
    }

    /// @inheritdoc IFeeKeeper
    function getOracle() public view override returns (IEACAggregatorProxy oracle) {
        oracle = storageLayout().oracle;
    }

    /// @inheritdoc IFeeKeeper
    function getAsset() public view override returns (address asset) {
        asset = storageLayout().asset;
    }

    /// @inheritdoc IFeeKeeper
    function getPeriod() public view override returns (uint256 period) {
        period = storageLayout().period;
    }

    /// @inheritdoc IFeeKeeper
    function getPreviousPeriod() public view override returns (uint256 previousPeriod) {
        previousPeriod = storageLayout().previousPeriod;
    }

    /// @inheritdoc IFeeKeeper
    function getLastClaim() public view override returns (uint256 lastClaim) {
        lastClaim = storageLayout().lastClaim;
    }

    /// @inheritdoc IFeeKeeper
    function getIsAllowedForManualRate(address token) public view override returns (bool isAllowed) {
        isAllowed = storageLayout().allowedManualTokens[token];
    }
}
