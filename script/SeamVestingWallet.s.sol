// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamVestingWallet} from "../src/SeamVestingWallet.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamVestingWalletDeployScript is Script {

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
        address initialOwner = vm.envOr("INITIAL_OWNER", deployerAddress);
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint64 durationSeconds = vm.envOr("DURATION_SECONDS", 3 * 365 days);
        

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", getChainId());

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        SeamVestingWallet vestingWalletImplementation = new SeamVestingWallet();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(vestingWalletImplementation),
            abi.encodeWithSelector(
                SeamVestingWallet.initialize.selector,
                initialOwner,
                beneficiary,
                Constants.SEAM_ADDRESS,
                durationSeconds
            )
        );

        console.log(
            "Deployed vesting wallet proxy to: ",
            address(proxy),
            " implementation: ",
            address(vestingWalletImplementation)
        );

        vm.stopBroadcast();
    }
}
