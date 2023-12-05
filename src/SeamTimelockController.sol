// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {SeamTimelockControllerStorage as Storage} from "./storage/SeamTimelockControllerStorage.sol";

/// @title SeamTimelockControl
/// @author Seamless Protocol
/// @notice TimelockController contract for the Seamless Protocol used for both short and long timelock controllers
contract SeamTimelockController is Initializable, TimelockControllerUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes timelock controller contract and inherited contracts.
    /// @param minDelay Minimum delay for timelock
    /// @param proposers Addresses that can propose and cancel operations
    /// @param executors Addresses that can execute operations
    /// @param admin Address that can modify timelock controller and upgrade this contract
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        external
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors, admin);
        __UUPSUpgradeable_init();

        Storage.layout().minDelay = minDelay;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @inheritdoc TimelockControllerUpgradeable
    function getMinDelay() public view virtual override returns (uint256) {
        return Storage.layout().minDelay;
    }

    /// @inheritdoc TimelockControllerUpgradeable
    function updateDelay(uint256 newDelay) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        emit MinDelayChange($.minDelay, newDelay);
        $.minDelay = newDelay;
    }
}
