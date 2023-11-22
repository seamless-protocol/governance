// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SeamGaugeStorage as Storage} from "../storage/SeamGaugeStorage.sol";

/// @title ISeamGauge
/// @notice Interface for the SEAM gauge contract.
interface ISeamGauge {
    event SetEmissionPerSecond(uint256 emissionRate);
    event AddNewCategory(
        string categoryDescription,
        uint256 minPercentage,
        uint256 maxPercentage
    );
    event RemoveCategory(uint256 indexed categoryIndex, string desciption);
    event Claim(
        uint256 indexed categoryIndex,
        address indexed receiver,
        uint256 amount,
        string categoryDescription
    );

    error InvalidPercentage();
    error InvalidReceiver();
    error ArrayLengthMismatch();
    error PercentageOutOfBounds();
    error InvalidPercentageSum();

    /// @notice Returns SEAM token address.
    function getSeam() external view returns (address);

    /// @notice Returns emission per second.
    function getEmissionPerSecond() external view returns (uint256);

    /// @notice Returns category information for given index.
    /// @param categoryIndex Index of category to return information for
    function getCategory(
        uint256 categoryIndex
    ) external view returns (Storage.CategoryConfig memory);

    /// @notice Returns all active categories.
    function getCategories()
        external
        view
        returns (Storage.CategoryConfig[] memory);

    /// @notice Sets emission per second.
    function setEmissionPerSecond(uint256) external;

    /// @notice Adds new category.
    /// @param description Description of category, e.g. "ILM LPs"
    /// @param minPercentage Minimum percentage of emission for this category, once set it cannot be modified
    /// @param maxPercentage Maximum percentage of emission for this category, once set it cannot be modified
    /// @dev Current percentage of category will be automatically set to zero and reciever will be set to zero address
    ///      which means that after adding category that category must be configured
    function addNewCategory(
        string memory description,
        uint256 minPercentage,
        uint256 maxPercentage
    ) external;

    /// @notice Removes category.
    /// @param categoryIndex Index of category to remove
    /// @dev For category to be removed it needs to have 0 percentage for emissions first
    function removeCategory(uint256 categoryIndex) external;

    /// @notice Sets receivers for categories.
    /// @param indexes Indexes of categories to set receivers for
    /// @param receivers Addresses of receivers
    /// @dev For each category only one receiver can be set, receivers and indexes arrays must be of the same length
    function setCategoryReceivers(
        uint256[] calldata indexes,
        address[] calldata receivers
    ) external;

    /// @notice Sets percentages for categories.
    /// @param indexes Indexes of categories to set percentages for
    /// @param percentages Percentages of emission for categories
    function setCategoryPercentages(
        uint256[] calldata indexes,
        uint256[] calldata percentages
    ) external;

    /// @notice Sets percentages and receivers for categories.
    /// @param indexes Indexes of categories to set percentages and receivers for
    /// @param percentages Percentages of emission for categories
    /// @param receivers Addresses of receivers
    function setCategoryPercetagesAndReceivers(
        uint256[] calldata indexes,
        uint256[] calldata percentages,
        address[] calldata receivers
    ) external;

    /// @notice Claims SEAM tokens for given category.
    /// @param categoryIndex Index of category to claim emission for
    function claim(uint256 categoryIndex) external;
}
