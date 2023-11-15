// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SeamEmissionManagerStorage as Storage} from "../storage/SeamEmissionManagerStorage.sol";

/// @title ISeamEmissionManager
/// @notice Interface for the SEAM emission manager contract.
interface ISeamEmissionManager {
    event SetEmissionPerSecond(uint256 emissionRate);
    event Claim(address indexed receiver, uint256 amount);

    error InvalidPercentage();
    error InvalidReceiver();
    error IncompatibleData();
    error PercentageOutOfBounds();
    error InvalidPercentageSum();

    /// @notice Returns SEAM token address.
    function getSeam() external view returns (address);

    /// @notice Returns emission per second.
    function getEmissionPerSecond() external view returns (uint256);

    /// @notice Returns all active categories.
    function getCategories() external view returns (Storage.CategoryConfig[] memory);

    /// @notice Sets emission per second.
    function setEmissionPerSecond(uint256) external;

    /// @notice Adds new category.
    /// @param description Description of category, e.g. "ILM LPs"
    /// @param minPercentage Minimum percentage of emission for this category, once set it cannot be modified
    /// @param maxPercentage Maximum percentage of emission for this category, once set it cannot be modified
    function addNewCategory(string memory description, uint256 minPercentage, uint256 maxPercentage) external;

    /// @notice Sets receivers for categories.
    /// @param indexes Indexes of categories to set receivers for
    /// @param receivers Addresses of receivers
    function setCategoryReceivers(uint256[] calldata indexes, address[] calldata receivers) external;

    /// @notice Sets percentages for categories.
    /// @param indexes Indexes of categories to set percentages for
    /// @param percentages Percentages of emission for categories
    function setCategoryPercentages(uint256[] calldata indexes, uint256[] calldata percentages) external;

    /// @notice Sets percentages and receivers for categories.
    /// @param indexes Indexes of categories to set percentages and receivers for
    /// @param percentages Percentages of emission for categories
    /// @param receivers Addresses of receivers
    function setCategoriesPercetagesAndReceivers(
        uint256[] calldata indexes,
        uint256[] calldata percentages,
        address[] calldata receivers
    ) external;

    /// @notice Claims SEAM tokens for given category.
    /// @param categoryIndex Index of category to claim emission for
    function claim(uint256 categoryIndex) external;
}
