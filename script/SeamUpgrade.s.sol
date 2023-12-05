// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Seam} from "../src/Seam.sol";

contract SeamUpgradeScript is Script {
    address constant PROXY_ADDRESS = address(0);
    bool constant UPGRADE_PROXY = false; // false if upgrade must be performed from a multisig or governance

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

        console.log("Deploying new implementation...");

        vm.startBroadcast(deployerPrivateKey);

        Seam tokenImplementation = new Seam();

        console.log("Deployed new implementation: ", address(tokenImplementation));

        if (UPGRADE_PROXY && PROXY_ADDRESS != address(0)) {
            UUPSUpgradeable proxy = UUPSUpgradeable(PROXY_ADDRESS);

            proxy.upgradeToAndCall(address(tokenImplementation), abi.encode());

            console.log(
                "Proxy implementation updated. Proxy: ",
                address(proxy),
                " implementation:",
                address(tokenImplementation)
            );
        }

        vm.stopBroadcast();
    }
}
