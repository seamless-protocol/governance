// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController} from "aave-v3-periphery/contracts/rewards/RewardsController.sol";
import {InitializableAdminUpgradeabilityProxy} from
    "aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";

library RewardsControllerUtils {
    function deployRewardsController(address emissionManager, address admin) internal returns (RewardsController) {
        // Deploy implementation
        RewardsController implementation = new RewardsController(emissionManager);
        implementation.initialize(address(0));

        // Deploy and initialize proxy
        InitializableAdminUpgradeabilityProxy proxy = new InitializableAdminUpgradeabilityProxy();
        proxy.initialize(
            address(implementation),
            admin,
            abi.encodeWithSelector(RewardsController.initialize.selector, emissionManager)
        );

        return RewardsController(address(proxy));
    }
}
