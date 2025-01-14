// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IEmissionManager} from "@aave/periphery-v3/contracts/rewards/interfaces/IEmissionManager.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {ITransferStrategyBase} from "@aave/periphery-v3/contracts/rewards/interfaces/ITransferStrategyBase.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardKeeperStorage as Storage} from "../storage/RewardKeeperStorage.sol";
import {ERC20TransferStrategy} from "../transfer-strategies/ERC20TransferStrategy.sol";

contract RewardKeeper is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    event ClaimedAndSetRate(address[] rewards, uint88[] rates);
    event SetEmissionManager(address emissionManager);
    event SetPool(address pool);
    event SetPeriod(uint256 period);

    error isZeroAddress(address target);
    error InsufficientTimeElapsed();
    error InvalidPeriod();
    error InvalidRewardToken();

    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address constant ORACLE_MOCK = 0x602823807C919A92B63cF5C126387c4759976072;

    modifier isNotZeroAddress(address target) {
        if (target == address(0)) {
            revert isZeroAddress(target);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    function initialize(address pool, address emissionManager, address initialAdmin, address stkSeam)
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __Pausable_init();

        Storage.Layout storage $ = Storage.layout();
        $.manager = IEmissionManager(emissionManager);
        $.controller = IRewardsController($.manager.getRewardsController());
        $.pool = IPool(pool);
        $.period = 1 days;
        $.lastClaim = block.timestamp;
        $.asset = stkSeam;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    /// @notice EmissionManager requires "rewardToken" address be msg.sender
    /// @dev Could use "ConfigureAssets" instead, but that requires oracle and transferStrategy addresses.

    function claimAndSetRate() external whenNotPaused {
        Storage.Layout storage $ = Storage.layout();
        // check if period has elapsed, update lastClaim
        if ($.lastClaim > block.timestamp - $.previousPeriod) revert InsufficientTimeElapsed();
        $.lastClaim = block.timestamp;
        $.previousPeriod = $.period;

        address[] memory rewardTokens = $.pool.getReservesList();

        // claim rewards
        // assume its coming to this contract for now
        $.pool.mintToTreasury(rewardTokens);

        // get new Emission rates
        uint88[] memory newRates = new uint88[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; i++) {
            IERC20 token = IERC20(rewardTokens[i]);

            // withdraw reward tokens
            $.pool.withdraw(rewardTokens[i], type(uint256).max, address(this));

            uint256 balance = token.balanceOf(address(this));

            // there will be dust from rounding here... it can stay in the contract and get accounted for next time.
            uint88 rate = uint88((balance) / $.period);
            newRates[i] = rate;

            ERC20TransferStrategy transferStrategy =
                ERC20TransferStrategy($.controller.getTransferStrategy(rewardTokens[i]));

            if (address(transferStrategy) == address(0)) {
                RewardsDataTypes.RewardsConfigInput[] memory config = new RewardsDataTypes.RewardsConfigInput[](1);
                transferStrategy = new ERC20TransferStrategy(token, address($.controller), address(this));
                config[0].emissionPerSecond = 0;
                config[0].totalSupply = token.totalSupply(); // Not sure if this is correct...
                config[0].distributionEnd = uint32(block.timestamp + $.period);
                config[0].asset = $.asset;
                config[0].reward = rewardTokens[i];
                config[0].transferStrategy = ITransferStrategyBase(address(transferStrategy));
                config[0].rewardOracle = IEACAggregatorProxy(ORACLE_MOCK);
                $.manager.configureAssets(config);
            } else {
                // set distributonEnd here
                $.manager.setDistributionEnd($.asset, rewardTokens[i], uint32(block.timestamp + $.period));
            }

            // ensures dust is not sent.
            token.transfer(address(transferStrategy), rate * $.period);
        }

        // set emissions per second
        $.manager.setEmissionPerSecond($.asset, rewardTokens, newRates);

        emit ClaimedAndSetRate(rewardTokens, newRates);
    }

    function emergencyWithdrawalFromTransferStrategy(address token, address to, uint256 amt) external isNotZeroAddress(to) isNotZeroAddress(token) onlyRole(MANAGER_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        address transferStrategy = $.controller.getTransferStrategy(token);
        if (transferStrategy == address(0)) revert InvalidRewardToken();
        ITransferStrategyBase(transferStrategy).emergencyWithdrawal(token, to, amt);
    }

    function setEmissionManager(address emissionManager)
        external
        isNotZeroAddress(emissionManager)
        onlyRole(MANAGER_ROLE)
    {
        Storage.Layout storage $ = Storage.layout();
        $.manager = IEmissionManager(emissionManager);
        emit SetEmissionManager(emissionManager);
    }

    function setPool(address newPool) external isNotZeroAddress(newPool) onlyRole(MANAGER_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        $.pool = IPool(newPool);
        emit SetPool(newPool);
    }

    function setPeriod(uint256 newPeriod) external onlyRole(MANAGER_ROLE) {
        if (newPeriod == 0) revert InvalidPeriod();
        Storage.Layout storage $ = Storage.layout();
        $.period = newPeriod;
        emit SetPeriod(newPeriod);
    }

    function getLayout() external view returns (Storage.Layout memory) {
        return Storage.layout();
    }
}
