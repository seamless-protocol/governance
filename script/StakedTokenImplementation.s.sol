// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {StakedToken} from "../src/StakedToken.sol";

contract StakedTokenImplementation is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying new implementation...");

        vm.startBroadcast(deployerPrivateKey);

        StakedToken newImplementation = new StakedToken();

        console.log("Deployed new implementation: ", address(newImplementation));

        vm.stopBroadcast();
    }
}
