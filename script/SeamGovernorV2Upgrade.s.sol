// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {SeamGovernorV2} from "../src/SeamGovernorV2.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamGovernorV2Upgrade is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying new implementation...");

        vm.startBroadcast(deployerPrivateKey);

        SeamGovernorV2 newImplementation = new SeamGovernorV2();

        console.log("Deployed new implementation: ", address(newImplementation));

        vm.stopBroadcast();
    }
}
