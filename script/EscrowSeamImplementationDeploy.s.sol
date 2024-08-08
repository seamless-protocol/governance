// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {EscrowSeam} from "../src/EscrowSeam.sol";

contract EscrowSeamImplementationDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        EscrowSeam esSEAM = new EscrowSeam();
        console.log("EscrowSeam implementation contract deployed at: ", address(esSEAM));

        vm.stopBroadcast();
    }
}
