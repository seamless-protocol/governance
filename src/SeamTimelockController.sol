// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title SeamTimelockControl
 * @author Seamless Protocol
 * @notice TimelockController contract for the Seamless Protocol used for both short and long timelock controllers
 */
contract SeamTimelockController is
    Initializable,
    TimelockControllerUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

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
    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) external initializer {
        __TimelockController_init(minDelay, proposers, executors, admin);
        __UUPSUpgradeable_init();
        _grantRole(UPGRADER_ROLE, admin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
