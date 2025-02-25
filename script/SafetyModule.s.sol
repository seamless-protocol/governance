// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InitializableAdminUpgradeabilityProxy} from "@aave/core-v3/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";
import {StakedToken} from "../src/safety-module/StakedToken.sol";
import {RewardKeeper} from "../src/safety-module/RewardKeeper.sol";
import {Constants} from "../src/library/Constants.sol";

contract SafetyModule is Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        StakedToken stakedTokenImplementation = new StakedToken();
        ERC1967Proxy stakedTokenProxy = new ERC1967Proxy(
            address(stakedTokenImplementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                Constants.SEAM_ADDRESS,
                deployerAddress,
                "Staked SEAM", // "stakedSEAM",
                "stkSEAM", //"stkSEAM",
                7 days,
                1 days
            )
        );
        StakedToken stkToken = StakedToken(address(stakedTokenProxy));
        console.log("Deployed StakedToken proxy to: ", address(stakedTokenProxy), " implementation: ", address(stakedTokenImplementation));

        RewardKeeper rewardKeeperImplementation = new RewardKeeper();
        ERC1967Proxy rewardKeeperProxy = new ERC1967Proxy(
            address(rewardKeeperImplementation),
            abi.encodeWithSelector(
                RewardKeeper.initialize.selector,
                Constants.POOL_ADDRESS,
                deployerAddress,
                address(stkToken),
                Constants.ORACLE_PLACEHOLDER,
                Constants.TREASURY_ADDRESS,
                Constants.STATIC_ATOKEN_FACTORY
            )
        );
        RewardKeeper rewardKeeper = RewardKeeper(address(rewardKeeperProxy));
        console.log("Deployed RewardKeeper to: ", address(rewardKeeperProxy), " implementation: ", address(rewardKeeperImplementation));

        RewardsController rewardsControllerImplementation = new RewardsController(address(rewardKeeper));
        rewardsControllerImplementation.initialize(address(0));

        InitializableAdminUpgradeabilityProxy rewardControllerProxy = new InitializableAdminUpgradeabilityProxy();

        rewardControllerProxy.initialize(
            address(rewardsControllerImplementation),
            Constants.SHORT_TIMELOCK_ADDRESS,
            abi.encodeWithSelector(
                RewardsController.initialize.selector,
                address(rewardKeeper)
            )
        );
        
        console.log("Deployed RewardsController to: ", address(rewardControllerProxy), " implementation: ", address(rewardsControllerImplementation));

        // set reward controller on stkToken and reward keeper
        rewardKeeper.setRewardsController(address(rewardControllerProxy));
        stkToken.setController(address(rewardControllerProxy));

        vm.stopBroadcast();
    }
}
