// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";
import {StakedToken} from "../src/safety-module/StakedToken.sol";
import {RewardKeeper} from "../src/safety-module/RewardKeeper.sol";
import {Constants} from "../src/library/Constants.sol";

contract SafetyModule is Script {
    function getChainId() public view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address asset = address(Constants.SEAM_ADDRESS);
        address pool = address(Constants.POOL_ADDRESS);
        address oracle = address(Constants.ORACLE_PLACEHOLDER);
        address treasury = address(Constants.TREASURY_ADDRESS);
        address staticATokenFactory = address(Constants.STATIC_ATOKEN_FACTORY);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", getChainId());

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        StakedToken implementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                asset,
                deployerAddress,
                "Staked SEAM", // "stakedSEAM",
                "stkSEAM", //"stkSEAM",
                7 days,
                1 days
            )
        );
        StakedToken stkToken = StakedToken(address(proxy));
        console.log("Deployed stkSEAM proxy to: ", address(proxy), " implementation: ", address(implementation));

        RewardKeeper implementation2 = new RewardKeeper();
        proxy = new ERC1967Proxy(
            address(implementation2),
            abi.encodeWithSelector(
                RewardKeeper.initialize.selector,
                pool,
                deployerAddress,
                address(stkToken),
                oracle,
                treasury,
                staticATokenFactory
            )
        );
        RewardKeeper rewardKeeper = RewardKeeper(address(proxy));
        console.log("Deployed RewardKeeper to: ", address(proxy), " implementation: ", address(implementation2));

        RewardsController controller = new RewardsController(address(rewardKeeper));
        console.log("Deployed controller to ", address(controller));

        // set reward controller on stkToken and reward keeper
        rewardKeeper.setRewardsController(address(controller));
        stkToken.setController(address(controller));

        vm.stopBroadcast();
    }
}
