// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ISeamEmissionManager} from "./interfaces/ISeamEmissionManager.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SeamEmissionManagerStorage as Storage} from "./storage/SeamEmissionManagerStorage.sol";

/// @title SeamEmissionManager
/// @author Seamless Protocol
/// @notice This contract is responsible for managing SEAM token emission.
/// @dev This contract should send SEAM tokens to each category as per their percentage.
contract SeamEmissionManager is ISeamEmissionManager, Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    uint256 public constant BASE_PERCENTAGE = 1000;
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    /// @param _seam SEAM token address
    /// @param _emissionPerSecond Emission per second
    /// @param _initialAdmin Initial admin of the contract
    /// @param _claimer Address that can claim SEAM tokens
    function initialize(address _seam, uint256 _emissionPerSecond, address _initialAdmin, address _claimer)
        external
        initializer
    {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(CLAIMER_ROLE, _claimer);

        Storage.Layout storage $ = Storage.layout();
        $.seam = IERC20(_seam);
        $.emissionPerSecond = _emissionPerSecond;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @inheritdoc ISeamEmissionManager
    function getSeam() external view returns (address) {
        return address(Storage.layout().seam);
    }

    /// @inheritdoc ISeamEmissionManager
    function getEmissionPerSecond() external view returns (uint256) {
        return Storage.layout().emissionPerSecond;
    }

    /// @inheritdoc ISeamEmissionManager
    function getCategory(uint256 categoryIndex) public view returns (Storage.CategoryConfig memory) {
        return Storage.layout().categories[categoryIndex];
    }

    /// @inheritdoc ISeamEmissionManager
    function getCategories() external view returns (Storage.CategoryConfig[] memory) {
        return Storage.layout().categories;
    }

    /// @inheritdoc ISeamEmissionManager
    function setEmissionPerSecond(uint256 emissionPerSecond) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Storage.layout().emissionPerSecond = emissionPerSecond;
        emit SetEmissionPerSecond(emissionPerSecond);
    }

    /// @inheritdoc ISeamEmissionManager
    function addNewCategory(string memory description, uint256 minPercentage, uint256 maxPercentage)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (minPercentage > maxPercentage || maxPercentage > BASE_PERCENTAGE) {
            revert InvalidPercentage();
        }

        Storage.layout().categories.push(
            Storage.CategoryConfig({
                description: description,
                minPercentage: minPercentage,
                maxPercentage: maxPercentage,
                percentage: 0,
                lastClaimedTimestamp: uint64(block.timestamp),
                receiver: address(0)
            })
        );

        emit AddNewCategory(description, minPercentage, maxPercentage);
    }

    // @inheritdoc ISeamEmissionManager
    function removeCategory(uint256 categoryIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Storage.CategoryConfig[] storage categories = Storage.layout().categories;

        string memory description = categories[categoryIndex].description;
        categories[categoryIndex] = categories[categories.length - 1];
        categories.pop();

        _validateSumOfPercentages();

        emit RemoveCategory(categoryIndex, description);
    }

    /// @inheritdoc ISeamEmissionManager
    function setCategoryReceivers(uint256[] calldata indexes, address[] calldata receivers)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (indexes.length != receivers.length) {
            revert ArrayLengthMismatch();
        }

        Storage.Layout storage $ = Storage.layout();
        for (uint256 i = 0; i < indexes.length; i++) {
            if (receivers[i] == address(0)) {
                revert InvalidReceiver();
            }
            Storage.layout().categories[indexes[i]].receiver = receivers[i];
        }
    }

    /// @inheritdoc ISeamEmissionManager
    function setCategoryPercentages(uint256[] calldata indexes, uint256[] calldata percentages)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (indexes.length != percentages.length) {
            revert ArrayLengthMismatch();
        }

        Storage.Layout storage $ = Storage.layout();
        for (uint256 i = 0; i < indexes.length; i++) {
            Storage.CategoryConfig storage category = $.categories[indexes[i]];

            if (percentages[i] > category.maxPercentage || percentages[i] < category.minPercentage) {
                revert PercentageOutOfBounds();
            }
            category.percentage = percentages[i];
        }

        _validateSumOfPercentages();
    }

    /// @inheritdoc ISeamEmissionManager
    function setCategoryPercetagesAndReceivers(
        uint256[] calldata indexes,
        uint256[] calldata percentages,
        address[] calldata receivers
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (indexes.length != percentages.length || indexes.length != receivers.length) {
            revert ArrayLengthMismatch();
        }

        Storage.Layout storage $ = Storage.layout();
        for (uint256 i = 0; i < indexes.length; i++) {
            if (receivers[i] == address(0)) {
                revert InvalidReceiver();
            }

            Storage.CategoryConfig storage category = $.categories[indexes[i]];

            if (percentages[i] > category.maxPercentage || percentages[i] < category.minPercentage) {
                revert PercentageOutOfBounds();
            }
            category.percentage = percentages[i];
            category.receiver = receivers[i];
        }

        _validateSumOfPercentages();
    }

    /// @inheritdoc ISeamEmissionManager
    function claim(uint256 categoryIndex) external onlyRole(CLAIMER_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        Storage.CategoryConfig storage category = $.categories[categoryIndex];

        uint256 emissionPerSecond = $.emissionPerSecond;
        uint64 lastClaimedTimestamp = category.lastClaimedTimestamp;
        uint64 currentTimestamp = uint64(block.timestamp);
        uint256 emissionAmount = Math.mulDiv(
            (currentTimestamp - lastClaimedTimestamp) * emissionPerSecond, category.percentage, BASE_PERCENTAGE
        );

        category.lastClaimedTimestamp = currentTimestamp;
        SafeERC20.safeTransfer($.seam, category.receiver, emissionAmount);

        emit Claim(categoryIndex, category.receiver, emissionAmount, category.description);
    }

    /// @notice Validates that sum of percentages for all categories is 100%.
    function _validateSumOfPercentages() private view {
        Storage.Layout storage $ = Storage.layout();
        uint256 sumOfPercentages = 0;
        for (uint256 i = 0; i < $.categories.length; i++) {
            sumOfPercentages += $.categories[i].percentage;
        }
        if (sumOfPercentages != BASE_PERCENTAGE) {
            revert InvalidPercentageSum();
        }
    }
}
