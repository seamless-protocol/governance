// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/**
 * @title EscrowSeam
 * @author Seamless Protocol
 * @dev This contract is vesting contract for SEAM token.
 */
contract EscrowSeam is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using Math for uint256;

    struct VestingData {
        uint256 claimableAmount;
        uint256 unvestPerSecond;
        uint256 vestingEndsAt;
        uint256 lastUpdatedTimestamp;
    }

    uint256 public vestingDuration;

    mapping(address => VestingData) public vestingInfo;

    function initialize(
        uint256 _vestingDuration,
        address _initialOwner
    ) public initializer {
        __ERC20_init("Escrow Seamless", "esSEAM");
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        vestingDuration = _vestingDuration;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function deposit(address account, uint256 amount) external {
        _updateVesting(account);

        VestingData storage vestingData = vestingInfo[account];

        uint256 timeUntilEnd = vestingData.vestingEndsAt -
            Math.min(block.timestamp, vestingData.vestingEndsAt);
        uint256 currVestingAmount = vestingData.unvestPerSecond * timeUntilEnd;
        uint256 newVestingPeriodDuration = ((currVestingAmount * timeUntilEnd) +
            (amount * vestingDuration)) / (currVestingAmount + amount);

        vestingData.unvestPerSecond = ((currVestingAmount + amount) /
            newVestingPeriodDuration);
        vestingData.vestingEndsAt = block.timestamp + newVestingPeriodDuration;
    }

    function _updateVesting(address account) private {
        VestingData storage vestingData = vestingInfo[account];
        uint256 timeDiff = Math.min(
            block.timestamp,
            vestingData.vestingEndsAt
        ) - vestingData.lastUpdatedTimestamp;
        uint256 unvestedAmount = timeDiff * vestingData.unvestPerSecond;

        vestingData.claimableAmount += unvestedAmount;
        vestingData.lastUpdatedTimestamp = block.timestamp;
    }
}
