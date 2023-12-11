// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamEmissionManager} from "../src/SeamEmissionManager.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamEmissionManagerDeploy is Script {
    uint64 constant EMISSION_START_TIMESTAMP = 0;
    uint256 constant EMISSIONS_PER_SECOND = 0;

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

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", getChainId());

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        SeamEmissionManager implementation = new SeamEmissionManager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                SeamEmissionManager.initialize.selector,
                Constants.SEAM_ADDRESS,
                EMISSIONS_PER_SECOND,
                Constants.LONG_TIMELOCK_ADDRESS,
                Constants.SHORT_TIMELOCK_ADDRESS,
                EMISSION_START_TIMESTAMP
            )
        );
        console.log(
            "Deployed SeamEmissionManager proxy to: ", address(proxy), " implementation: ", address(implementation)
        );

        vm.stopBroadcast();
    }
}
