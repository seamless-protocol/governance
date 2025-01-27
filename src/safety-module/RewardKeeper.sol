// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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
import {ERC20TransferStrategy} from "../transfer-strategies/ERC20TransferStrategy.sol";

contract RewardKeeper is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, IRewardKeeper {
    using SafeERC20 for IERC20;

    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

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
    function initialize(address pool, address initialAdmin, address stkSeam, address oracle) external initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();

        Storage.Layout storage $ = Storage.layout();

        $.pool = IPool(pool);
        $.oracle = IEACAggregatorProxy(oracle);
        $.period = 1 days;
        $.lastClaim = block.timestamp;
        $.asset = stkSeam;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function claimAndSetRate() external override whenNotPaused {
        Storage.Layout storage $ = Storage.layout();

        IPool pool = getPool();
        IRewardsController controller = getController();
        address asset = getAsset();
        address[] memory rewardTokens = pool.getReservesList();
        uint256 period = getPeriod();
        uint256 nextMidnight = ((block.timestamp / period) + 1) * period;
        period = nextMidnight - block.timestamp;
        

        // check if period has elapsed, update lastClaim
        if ($.lastClaim > block.timestamp - $.previousPeriod) revert InsufficientTimeElapsed();
        $.lastClaim = block.timestamp;
        $.previousPeriod = period;

        // claim rewards
        // assume its coming to this contract for now
        
        pool.mintToTreasury(rewardTokens);

        // get new Emission rates
        uint88[] memory newRates = new uint88[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; i++) {
            IERC20 token = IERC20(rewardTokens[i]);

            // withdraw reward tokens
            pool.withdraw(rewardTokens[i], type(uint256).max, address(this));

            uint256 balance = token.balanceOf(address(this));

            // there will be dust from rounding here... it can stay in the contract and get accounted for next time.
            uint88 rate = uint88((balance) / period);
            newRates[i] = rate;

            ERC20TransferStrategy transferStrategy =
                ERC20TransferStrategy(controller.getTransferStrategy(rewardTokens[i]));

            if (address(transferStrategy) == address(0)) {
                RewardsDataTypes.RewardsConfigInput[] memory config = new RewardsDataTypes.RewardsConfigInput[](1);
                transferStrategy = new ERC20TransferStrategy(token, address(controller), address(this));
                config[0].emissionPerSecond = 0;
                config[0].totalSupply = token.totalSupply(); // Not sure if this is correct...
                config[0].distributionEnd = uint32(block.timestamp + period);
                config[0].asset = asset;
                config[0].reward = rewardTokens[i];
                config[0].transferStrategy = ITransferStrategyBase(address(transferStrategy));
                config[0].rewardOracle = $.oracle;
                controller.configureAssets(config);
            } else {
                // set distributonEnd here
                controller.setDistributionEnd(asset, rewardTokens[i], uint32(block.timestamp + period));
            }

            // ensures dust is not sent.
            token.transfer(address(transferStrategy), rate * period);
        }

        // set emissions per second
        controller.setEmissionPerSecond(asset, rewardTokens, newRates);

        emit ClaimedAndSetRate(rewardTokens, newRates);
    }

    function emergencyWithdrawalFromTransferStrategy(address token, address to, uint256 amt)
        external
        override
        isNotZeroAddress(to)
        isNotZeroAddress(token)
        onlyRole(MANAGER_ROLE)
    {
        address transferStrategy = getController().getTransferStrategy(token);
        if (transferStrategy == address(0)) revert TransferStrategyNotSet();
        ITransferStrategyBase(transferStrategy).emergencyWithdrawal(token, to, amt);
    }

    function setRewardsController(address controller)
        external
        override
        isNotZeroAddress(controller)
        onlyRole(MANAGER_ROLE)
    {
        Storage.layout().controller = IRewardsController(controller);
        emit SetRewardsController(controller);
    }

    function setPool(address newPool) external override isNotZeroAddress(newPool) onlyRole(MANAGER_ROLE) {
        Storage.layout().pool = IPool(newPool);
        emit SetPool(newPool);
    }

    function setPeriod(uint256 newPeriod) external override onlyRole(MANAGER_ROLE) {
        if (newPeriod == 0) revert InvalidPeriod();
        Storage.layout().period = newPeriod;
        emit SetPeriod(newPeriod);
    }

    function getController() public view override returns (IRewardsController) {
        return Storage.layout().controller;
    }

    function getPool() public view override returns (IPool) {
        return Storage.layout().pool;
    }

    function getOracle() public view override returns (IEACAggregatorProxy) {
        return Storage.layout().oracle;
    }

    function getAsset() public view override returns (address) {
        return Storage.layout().asset;
    }

    function getPeriod() public view override returns (uint256) {
        return Storage.layout().period;
    }

    function getPreviousPeriod() public view override returns (uint256) {
        return Storage.layout().previousPeriod;
    }

    function getLastClaim() public view override returns (uint256) {
        return Storage.layout().lastClaim;
    }
}
