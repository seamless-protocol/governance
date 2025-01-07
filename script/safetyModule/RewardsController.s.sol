// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EmissionManager} from "@aave/periphery-v3/contracts/rewards/EmissionManager.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";
import {StakedToken} from "../../src/safetyModule/stakedToken.sol";

contract SafetyModuleDeploy is Script {
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
        address asset = vm.envAddress("ASSET");

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", getChainId());

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        EmissionManager manager = new EmissionManager(deployerAddress);
        console.log("Deployed EmissionManager to ", address(manager));

        RewardsController controller = new RewardsController(address(manager));
        console.log("Deployed controller to ", address(controller));

        StakedToken implementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                asset,
                address(controller),
                deployerAddress,
                "TEST", // "stakedSEAM",
                "TST", //"stkSEAM",
                7 days,
                1 days
            )
        );
        console.log("Deployed stkSEAM proxy to: ", address(proxy), " implementation: ", address(implementation));

        // deploy transferERC20TransferStrategy for all reward tokens

        // set transferStrategies

        // manager.configureAssets -> set stkSEAM address and reward tokens

        // deploy rewardKeeper

        // manager.setEmissionAdmin(address(rewardKeeper))
        vm.stopBroadcast();
    }
}
