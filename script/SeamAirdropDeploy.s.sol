// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Constants} from "../src/library/Constants.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamAirdrop} from "../src/airdrop/SeamAirdrop.sol";

contract SeamAirdropDeploy is Script {
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

        SeamAirdrop seamAirdrop = new SeamAirdrop(
            IERC20(Constants.SEAM_ADDRESS),
            Constants.MERKLE_ROOT,
            Constants.SHORT_TIMELOCK_ADDRESS
        );
        console.log("Deployed SeamAirdrop to: ", address(seamAirdrop));

        vm.stopBroadcast();
    }
}