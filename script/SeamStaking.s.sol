// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InitializableAdminUpgradeabilityProxy} from
    "aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";
import {RewardsController} from "static-a-token-v3/lib/aave-v3-periphery/contracts/rewards/RewardsController.sol";
import {StakedToken} from "../src/StakedToken.sol";
import {FeeKeeper} from "../src/FeeKeeper.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamStaking is Script {
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
        console.log(
            "Deployed StakedToken proxy to: ",
            address(stakedTokenProxy),
            " implementation: ",
            address(stakedTokenImplementation)
        );

        FeeKeeper feeKeeperImplementation = new FeeKeeper();
        ERC1967Proxy feeKeeperProxy = new ERC1967Proxy(
            address(feeKeeperImplementation),
            abi.encodeWithSelector(
                FeeKeeper.initialize.selector, deployerAddress, address(stkToken), Constants.ORACLE_PLACEHOLDER
            )
        );
        FeeKeeper feeKeeper = FeeKeeper(address(feeKeeperProxy));
        console.log(
            "Deployed FeeKeeper to: ", address(feeKeeperProxy), " implementation: ", address(feeKeeperImplementation)
        );

        RewardsController rewardsControllerImplementation = new RewardsController(address(feeKeeper));
        rewardsControllerImplementation.initialize(address(0));

        InitializableAdminUpgradeabilityProxy rewardControllerProxy = new InitializableAdminUpgradeabilityProxy();

        rewardControllerProxy.initialize(
            address(rewardsControllerImplementation),
            Constants.SHORT_TIMELOCK_ADDRESS,
            abi.encodeWithSelector(RewardsController.initialize.selector, address(feeKeeper))
        );

        console.log(
            "Deployed RewardsController to: ",
            address(rewardControllerProxy),
            " implementation: ",
            address(rewardsControllerImplementation)
        );

        // set reward controller on stkToken and reward keeper
        feeKeeper.setRewardsController(address(rewardControllerProxy));
        stkToken.setController(address(rewardControllerProxy));

        vm.stopBroadcast();
    }
}
