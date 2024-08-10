// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamVestingWallet} from "../src/SeamVestingWallet.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamVestingWalletDeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address initialOwner = vm.envOr("INITIAL_OWNER", deployerAddress);
        address finalOwner = vm.envOr("FINAL_OWNER", deployerAddress);
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint64 durationSeconds = uint64(vm.envOr("DURATION_SECONDS", uint256(3 * 365 days)));
        uint64 startTimestamp = uint64(vm.envOr("START_TIMESTAMP", block.timestamp));

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

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

        SeamVestingWallet vestingWallet = SeamVestingWallet(address(proxy));

        if (initialOwner == deployerAddress) {
            vestingWallet.setStart(startTimestamp);

            console.log("Start timestamp set to: ", startTimestamp);

            vestingWallet.transferOwnership(finalOwner);

            console.log("Transfered ownership to: ", finalOwner);
        }

        vm.stopBroadcast();
    }
}
