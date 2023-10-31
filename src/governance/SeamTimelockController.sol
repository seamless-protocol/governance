// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TimelockControllerUpgradeable} from "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title SeamTimelockControl
 * @author Seamless Protocol
 * @notice TimelockControll contract for the Seamless Protocol used for both short and long timelock controllers
 */
contract SeamTimelockController is TimelockControllerUpgradeable {
    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) external initializer {
        __TimelockController_init(minDelay, proposers, executors, admin);
    }
}
