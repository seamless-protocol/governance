// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title SeamTimelockControl
 * @author Seamless Protocol
 * @notice TimelockController contract for the Seamless Protocol used for both short and long timelock controllers
 */
contract SeamTimelockController is Initializable, TimelockControllerUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        external
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors, admin);
        __UUPSUpgradeable_init();
        _grantRole(UPGRADER_ROLE, admin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
