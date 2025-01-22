// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StakedToken} from "../../src/safety-module/StakedToken.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {StakedTokenStorage} from "../../src/storage/StakedTokenStorage.sol";

contract StakedTokenTester is StakedToken {
    // ------------------------------
    //  REWARDS CONTROLLER
    // ------------------------------
    function setRewardsControllerForTest(IRewardsController newController) external {
        StakedTokenStorage.layout().rewardsController = newController;
    }

    function getRewardsControllerForTest() external view returns (address) {
        return address(StakedTokenStorage.layout().rewardsController);
    }

    // ------------------------------
    //  COOLDOWN_SECONDS
    // ------------------------------
    function setCooldownSecondsForTest(uint256 cooldown) external {
        StakedTokenStorage.layout().cooldownSeconds = cooldown;
    }

    function getCooldownSecondsForTest() external view returns (uint256) {
        return StakedTokenStorage.layout().cooldownSeconds;
    }

    // ------------------------------
    //  UNSTAKE_WINDOW
    // ------------------------------
    function setUnstakeWindowForTest(uint256 window) external {
        StakedTokenStorage.layout().unstakeWindow = window;
    }

    function getUnstakeWindowForTest() external view returns (uint256) {
        return StakedTokenStorage.layout().unstakeWindow;
    }

    // ------------------------------
    //  STAKERS_COOLDOWNS mapping
    // ------------------------------
    function setStakersCooldownForTest(address user, uint256 timestamp) external {
        StakedTokenStorage.layout().stakersCooldowns[user] = timestamp;
    }

    function getStakersCooldownForTest(address user) external view returns (uint256) {
        return StakedTokenStorage.layout().stakersCooldowns[user];
    }
}
