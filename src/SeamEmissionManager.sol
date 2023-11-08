// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SeamEmissionManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public constant BASE_PERCENTAGE = 1000;

    struct Category {
        string description;
        uint256 minPercentage;
        uint256 maxPercentage;
        uint256 percentage;
        address receiver;
    }

    struct SeamEmissionManagerStorage {
        uint256 epochDuration;
        uint256 emissionPerEpoch;
        Category[] categories;
    }

    bytes32 private constant SeamEmissionManagerStorageLocation =
        0x6393c68bbda65a43373480543c4f1ff15eb61969ce223f59d8fd1889e26cc300;

    function _getSeamEmissionManagerStorage() private pure returns (SeamEmissionManagerStorage storage $) {
        assembly {
            $.slot := SeamEmissionManagerStorageLocation
        }
    }

    error InvalidPercentage();
    error InvalidReceiver();
    error InvalidPercentagesSum();

    function initialize(address initialOwner, uint256 epochDuration, uint256 emissionPerEpoch) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        $.epochDuration = epochDuration;
        $.emissionPerEpoch = emissionPerEpoch;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function getEmissionPerEpoch() external view returns (uint256) {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        return $.emissionPerEpoch;
    }

    function getEpochDuration() external view returns (uint256) {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        return $.epochDuration;
    }

    function getCategory(uint256 index)
        external
        view
        returns (
            string memory description,
            uint256 minPercentage,
            uint256 maxPercentage,
            uint256 percentage,
            address receiver
        )
    {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        Category storage category = $.categories[index];
        return (
            category.description, category.minPercentage, category.maxPercentage, category.percentage, category.receiver
        );
    }

    function setEpochDuration(uint256 epochDuration) external onlyOwner {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        $.epochDuration = epochDuration;
    }

    function setEmisisonPerEpoch(uint256 emissionPerEpoch) external onlyOwner {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        $.emissionPerEpoch = emissionPerEpoch;
    }

    function addNewCategory(string memory description, uint256 minPercentage, uint256 maxPercentage)
        external
        onlyOwner
    {
        if (minPercentage > maxPercentage || maxPercentage > BASE_PERCENTAGE) {
            revert InvalidPercentage();
        }
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        $.categories.push(
            Category({
                description: description,
                minPercentage: minPercentage,
                maxPercentage: maxPercentage,
                percentage: 0,
                receiver: address(0)
            })
        );
    }

    function setCategoryReceivers(uint256[] calldata index, address[] calldata receiver) external onlyOwner {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();

        if (index.length != receiver.length) {
            revert InvalidReceiver();
        }

        for (uint256 i = 0; i < index.length; i++) {
            Category storage category = $.categories[index[i]];
            if (category.receiver == address(0)) {
                revert InvalidReceiver();
            }
            category.receiver = receiver[i];
        }
    }

    function setCategoryPercentages(uint256[] calldata indexes, uint256[] calldata percentages) external onlyOwner {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();

        if (indexes.length != percentages.length) {
            revert InvalidPercentage();
        }

        for (uint256 i = 0; i < indexes.length; i++) {
            Category storage category = $.categories[indexes[i]];
            if (percentages[i] > category.maxPercentage || percentages[i] < category.minPercentage) {
                revert InvalidPercentage();
            }
            category.percentage = percentages[i];
        }

        _validateSumOfPercentages();
    }

    function setCategoryData(uint256 index, uint256 percentage, address receiver) external onlyOwner {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        Category storage category = $.categories[index];
        if (percentage > category.maxPercentage || percentage < category.minPercentage) {
            revert InvalidPercentage();
        }
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        category.percentage = percentage;
        category.receiver = receiver;

        _validateSumOfPercentages();
    }

    function _validateSumOfPercentages() private view {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        uint256 sumOfPercentages = 0;
        for (uint256 i = 0; i < $.categories.length; i++) {
            sumOfPercentages += $.categories[i].percentage;
        }
        if (sumOfPercentages != BASE_PERCENTAGE) {
            revert InvalidPercentagesSum();
        }
    }
}
