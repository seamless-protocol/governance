// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ISeamEmissionManager} from "./interfaces/ISeamEmissionManager.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {SeamEmissionManagerStorage as Storage} from "./storage/SeamEmissionManagerStorage.sol";

/// @title SeamEmissionManager
/// @author Seamless Protocol
/// @notice This contract is responsible for managing SEAM token emission.
contract SeamEmissionManager is ISeamEmissionManager, Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    /// @param seam SEAM token address
    /// @param emissionPerSecond Emission per second
    /// @param initialAdmin Initial admin of the contract
    function initialize(address seam, uint256 emissionPerSecond, address initialAdmin, address claimer, uint64 emissionStart)
        external
        initializer
    {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(CLAIMER_ROLE, initialAdmin);
        _grantRole(CLAIMER_ROLE, claimer);

        Storage.Layout storage $ = Storage.layout();
        $.seam = IERC20(seam);
        $.emissionPerSecond = emissionPerSecond;
        $.emissionStartTimestamp = uint64(emissionStart);
        $.lastClaimedTimestamp = uint64(emissionStart);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @inheritdoc ISeamEmissionManager
    function getSeam() external view returns (address) {
        return address(Storage.layout().seam);
    }

    /// @inheritdoc ISeamEmissionManager
    function getEmissionStartTimestamp() external view returns (uint64) {
        return Storage.layout().emissionStartTimestamp;
    }

    /// @inheritdoc ISeamEmissionManager
    function setEmissionStartTimestamp(uint64 emissionStartTimestamp) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        $.emissionStartTimestamp = emissionStartTimestamp;
        $.lastClaimedTimestamp = emissionStartTimestamp;
        emit SetEmissionStartTimestamp(emissionStartTimestamp);
    }

    /// @inheritdoc ISeamEmissionManager
    function getLastClaimedTimestamp() external view returns (uint64) {
        uint64 lastClaimedTimestamp = Storage.layout().lastClaimedTimestamp;
        return lastClaimedTimestamp > block.timestamp ? 0 : lastClaimedTimestamp;
    }

    /// @inheritdoc ISeamEmissionManager
    function getEmissionPerSecond() external view returns (uint256) {
        return Storage.layout().emissionPerSecond;
    }

    /// @inheritdoc ISeamEmissionManager
    function setEmissionPerSecond(uint256 emissionPerSecond) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Storage.layout().emissionPerSecond = emissionPerSecond;
        emit SetEmissionPerSecond(emissionPerSecond);
    }

    /// @inheritdoc ISeamEmissionManager
    function claim(address receiver) external onlyRole(CLAIMER_ROLE) {
        Storage.Layout storage $ = Storage.layout();

        uint64 emissionStartTimestamp = $.emissionStartTimestamp;
        if (emissionStartTimestamp > block.timestamp) {
            revert EmissionsNotStarted(emissionStartTimestamp);
        }

        uint256 emissionPerSecond = $.emissionPerSecond;
        uint64 lastClaimedTimestamp = $.lastClaimedTimestamp;
        uint64 currentTimestamp = uint64(block.timestamp);
        uint256 emissionAmount = (currentTimestamp - lastClaimedTimestamp) * emissionPerSecond;

        SafeERC20.safeTransfer($.seam, receiver, emissionAmount);
        $.lastClaimedTimestamp = currentTimestamp;

        emit Claim(receiver, emissionAmount);
    }
}
