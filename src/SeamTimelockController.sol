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
    /// @custom:storage-location erc7201:seamless.contracts.storage.SeamTimelockController
    struct SeamTimelockControllerStorage {
        uint256 _minDelay;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamTimelockController")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _SEAM_TIMELOCK_STORAGE_LOCATION =
        0x263ed6143c54408ffb31ea73e81969b42f560e7b9104812b019a9e78ab9b3c00;

    // solhint-disable-next-line var-name-mixedcase
    function _getSeamTimelockControllerStorage() private pure returns (SeamTimelockControllerStorage storage $) {
        assembly {
            $.slot := _SEAM_TIMELOCK_STORAGE_LOCATION
        }
    }

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

        // solhint-disable-next-line var-name-mixedcase
        SeamTimelockControllerStorage storage $ = _getSeamTimelockControllerStorage();

        $._minDelay = minDelay;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @inheritdoc TimelockControllerUpgradeable
    function getMinDelay() public view virtual override returns (uint256 duration) {
        // solhint-disable-next-line var-name-mixedcase
        SeamTimelockControllerStorage storage $ = _getSeamTimelockControllerStorage();
        return $._minDelay;
    }

    /// @inheritdoc TimelockControllerUpgradeable
    function updateDelay(uint256 newDelay) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        // solhint-disable-next-line var-name-mixedcase
        SeamTimelockControllerStorage storage $ = _getSeamTimelockControllerStorage();

        emit MinDelayChange($._minDelay, newDelay);
        $._minDelay = newDelay;
    }
}
