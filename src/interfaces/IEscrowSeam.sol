// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEscrowSeam is IERC20 {
    struct VestingData {
        uint256 claimableAmount;
        uint256 vestPerSecond;
        uint256 vestingEndsAt;
        uint256 lastUpdatedTimestamp;
    }

    struct EscrowSeamStorage {
        IERC20 seam;
        uint256 vestingDuration;
        mapping(address => VestingData) vestingInfo;
    }

    error NonTransferable();
    error ZeroAmount();

    event Deposit(address indexed from, address indexed onBehalfOf, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    function seam() external view returns (address);

    function vestingDuration() external view returns (uint256);

    function vestingInfo(address) external view returns (uint256, uint256, uint256, uint256);

    function getClaimableAmount(address) external view returns (uint256);

    function deposit(address, uint256) external;

    function claim(address) external;
}
