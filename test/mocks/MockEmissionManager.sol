// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {MockRewardsController} from "./MockRewardsController.sol";

contract MockEmissionManager {
    address internal rewardsController;

    constructor(address _rewardsController) {
        rewardsController = _rewardsController;
    }

    function getRewardsController() external view returns (IRewardsController) {
        return IRewardsController(rewardsController);
    }

    function setDistributionEnd(address, address, uint32) external {}
    function setEmissionPerSecond(address, address[] calldata, uint88[] calldata) external {}

    function configureAssets(RewardsDataTypes.RewardsConfigInput[] calldata config) external {
        // imitate setting rewards controller
        for (uint256 i; i < config.length; i++) {
            MockRewardsController(rewardsController)._addTransferStrategy(
                config[i].reward, address(config[i].transferStrategy)
            );
        }
    }
}
