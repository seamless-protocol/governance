// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IEmissionManager} from "@aave/periphery-v3/contracts/rewards/interfaces/IEmissionManager.sol";
import {RewardKeeperStorage as Storage} from "../storage/RewardKeeperStorage.sol";

contract RewardKeeper is UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    event ClaimedAndSetRate(address[] rewards, uint88[] rates);
    event SetEmissionManager(address emissionManager);
    event SetPool(address pool);
    event SetTreasury(address treasury);
    event SetPeriod(uint256 period);

    error isZeroAddress(address target);
    error InsufficientTimeElapsed();
    error InvalidPeriod();

    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    // bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    // TODO: include pausable?

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
    function initialize(address pool, address emissionManager, address initialAdmin, address treasury, address stkSeam)
        external
        initializer
    {
        __UUPSUpgradeable_init();

        Storage.Layout storage $ = Storage.layout();
        $.manager = IEmissionManager(emissionManager);
        $.pool = IPool(pool);
        $.treasury = treasury;
        $.period = 1 days;
        $.lastClaim = block.timestamp;
        $.asset = stkSeam;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// @notice EmissionManager requires "rewardToken" address be msg.sender
    /// @dev Could use "ConfigureAssets" instead, but that requires oracle and transferStrategy addresses.
    /// @dev can we get list of rewardTokens from some function? Passing it in is not great and a source of error.
    /// @param rewardTokens addresses of reward tokens
    function claimAndSetRate(address[] calldata rewardTokens) external {
        Storage.Layout storage $ = Storage.layout();
        // check if period has elapsed, update lastClaim
        if ($.lastClaim > block.timestamp - $.period) revert InsufficientTimeElapsed();
        $.lastClaim = block.timestamp;

        // Get previous balances for all rewards
        uint256[] memory balancesBefore = new uint256[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; i++) {
            balancesBefore[i] = IERC20(rewardTokens[i]).balanceOf($.treasury);
        }

        // claim rewards
        $.pool.mintToTreasury(rewardTokens);

        // get new Emission rates
        uint88[] memory newRates = new uint88[](rewardTokens.length);
        for (uint8 i; i < rewardTokens.length; i++) {
            uint256 balance = IERC20(rewardTokens[i]).balanceOf($.treasury);

            // there will be dust from rounding here... it will be small so we can ignore/collect in treasury OR track them...
            uint88 rate = uint88((balance - balancesBefore[i]) / $.period);
            newRates[i] = rate;

            // set distributonEnd here
            $.manager.setDistributionEnd($.asset, rewardTokens[i], uint32(block.timestamp + $.period));
        }

        // set emissions per second
        $.manager.setEmissionPerSecond($.asset, rewardTokens, newRates);

        emit ClaimedAndSetRate(rewardTokens, newRates);
    }

    function setEmissionManager(address emissionManager)
        external
        isNotZeroAddress(emissionManager)
        onlyRole("MANAGER_ROLE")
    {
        Storage.Layout storage $ = Storage.layout();
        $.manager = IEmissionManager(emissionManager);
        emit SetEmissionManager(emissionManager);
    }

    function setPool(address newPool) external isNotZeroAddress(newPool) onlyRole("MANAGER_ROLE") {
        Storage.Layout storage $ = Storage.layout();
        $.pool = IPool(newPool);
        emit SetPool(newPool);
    }

    function setTreasury(address newTreasury) external isNotZeroAddress(newTreasury) onlyRole("MANAGER_ROLE") {
        Storage.Layout storage $ = Storage.layout();
        $.treasury = newTreasury;
        emit SetPool(newTreasury);
    }

    function setPeriod(uint256 newPeriod) external onlyRole("MANAGER_ROLE") {
        if (newPeriod == 0) revert InvalidPeriod();
        Storage.Layout storage $ = Storage.layout();
        $.period = newPeriod;
        emit SetPeriod(newPeriod);
    }
}
