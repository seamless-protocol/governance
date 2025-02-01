// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract SeamGovernorV2UpgradeScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying and validating new implementation...");

        vm.startBroadcast(deployerPrivateKey);

        Options memory opts;

        address newImplementation = Upgrades.prepareUpgrade("SeamGovernorV2.sol", opts);

        console.log("Deployed new implementation: ", address(newImplementation));

        vm.stopBroadcast();
    }
}
