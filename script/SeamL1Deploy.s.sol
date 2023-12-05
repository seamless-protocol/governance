// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {SeamL1} from "../src/SeamL1.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamL1DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        SeamL1 seamL1 =
            new SeamL1(Constants.BASE_L1_BRIDGE, Constants.SEAM_ADDRESS, Constants.TOKEN_NAME, Constants.TOKEN_SYMBOL);

        console.log("SEAM bridged deployed to L1 at: ", address(seamL1));

        vm.stopBroadcast();
    }
}
