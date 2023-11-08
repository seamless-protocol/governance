// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SeamEmissionManager
 * @author Seamless Protocol
 * @notice This contract is responsible for managing SEAM token emission.
 */
contract SeamEmissionManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    event SetEmissionPerSecond(uint256 emissionRate);
    event Claim(address indexed receiver, uint256 amount);

    struct SeamEmissionManagerStorage {
        IERC20 seam;
        uint256 emissionPerSecond;
        uint64 lastClaimedTimestamp;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamEmissionManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SeamEmissionManagerStorageLocation =
        0x499527223a0cbf0f8120b81b4a5c3bfc177472cf818369c98e27b6304d0f5000;

    function _getSeamEmissionManagerStorage() private pure returns (SeamEmissionManagerStorage storage $) {
        assembly {
            $.slot := SeamEmissionManagerStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the token storage and inherited contracts.
     * @param seam SEAM token address
     * @param emissionPerSecond Emission per second
     * @param initialOwner Initial owner of the contract
     */
    function initialize(address seam, uint256 emissionPerSecond, address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        $.seam = IERC20(seam);
        $.emissionPerSecond = emissionPerSecond;
        $.lastClaimedTimestamp = uint64(block.timestamp);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Returns SEAM token address.
     */
    function getSeam() external view returns (address) {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        return address($.seam);
    }

    /**
     * @notice Returns last claimed timestamp.
     */
    function getLastClaimedTimestamp() external view returns (uint256) {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        return $.lastClaimedTimestamp;
    }

    /**
     * @notice Returns emission per second.
     */
    function getEmissionPerSecond() external view returns (uint256) {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        return $.emissionPerSecond;
    }

    /**
     * @notice Sets emission per second.
     */
    function setEmissionPerSecond(uint256 emissionPerSecond) external onlyOwner {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        $.emissionPerSecond = emissionPerSecond;
        emit SetEmissionPerSecond(emissionPerSecond);
    }

    /**
     * @notice Claims SEAM tokens and sends them to given address.
     * @param receiver Address to receive SEAM tokens
     */
    function claim(address receiver) external onlyOwner {
        SeamEmissionManagerStorage storage $ = _getSeamEmissionManagerStorage();
        uint256 emissionPerSecond = $.emissionPerSecond;
        uint64 lastClaimedTimestamp = $.lastClaimedTimestamp;
        uint64 currentTimestamp = uint64(block.timestamp);
        uint256 emissionAmount = (currentTimestamp - lastClaimedTimestamp) * emissionPerSecond;

        $.seam.transfer(receiver, emissionAmount);
        $.lastClaimedTimestamp = currentTimestamp;

        emit Claim(receiver, emissionAmount);
    }
}
