// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title SeamTimelockControl
 * @author Seamless Protocol
 * @notice TimelockController contract for the Seamless Protocol used for both short and long timelock controllers
 */
contract SeamTimelockController is Initializable, TimelockControllerUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes timelock controller contract and inherited contracts.
     * @param minDelay Minimum delay for timelock
     * @param proposers Addresses that can propose and cancel operations
     * @param executors Addresses that can execute operations
     * @param admin Address that can modify timelock controller and upgrade this contract
     */
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        external
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors, admin);
        __UUPSUpgradeable_init();
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function updateDelay(uint256 newDelay) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        TimelockControllerStorage storage $;
        assembly {
            $.slot := 0x9a37c2aa9d186a0969ff8a8267bf4e07e864c2f2768f5040949e28a624fb3600
        }

        emit MinDelayChange($._minDelay, newDelay);
        $._minDelay = newDelay;
    }
}
