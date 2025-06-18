// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamEmissionManagerV2} from "../src/SeamEmissionManagerV2.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamEmissionManagerV2Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        SeamEmissionManagerV2 implementation = new SeamEmissionManagerV2();

        console.log("Deployed SeamEmissionManagerV2 implementation: ", address(implementation));

        vm.stopBroadcast();
    }
}
