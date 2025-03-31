// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamVestingWalletV2} from "../src/SeamVestingWalletV2.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamVestingWalletV2DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address initialOwner = vm.envOr("INITIAL_OWNER", deployerAddress);
        address finalOwner = vm.envOr("FINAL_OWNER", deployerAddress);
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint64 durationSeconds = uint64(vm.envUint("DURATION_SECONDS"));
        uint64 cliffSeconds = uint64(vm.envUint("CLIFF_SECONDS"));
        uint64 startTimestamp = uint64(vm.envUint("START_TIMESTAMP"));
        uint64 lockupStartTimestamp = uint64(vm.envUint("LOCKUP_START_TIMESTAMP"));
        uint64 lockupEndTimestamp = uint64(vm.envUint("LOCKUP_END_TIMESTAMP"));

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        SeamVestingWalletV2 vestingWalletImplementation = new SeamVestingWalletV2();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(vestingWalletImplementation),
            abi.encodeWithSelector(
                SeamVestingWalletV2.initialize.selector,
                initialOwner,
                beneficiary,
                Constants.SEAM_ADDRESS,
                Constants.stkSEAM,
                startTimestamp,
                durationSeconds,
                cliffSeconds
            )
        );

        console.log(
            "Deployed vesting wallet proxy to: ",
            address(proxy),
            " implementation: ",
            address(vestingWalletImplementation)
        );

        SeamVestingWalletV2 vestingWallet = SeamVestingWalletV2(address(proxy));

        if (initialOwner == deployerAddress) {
            if (lockupStartTimestamp != 0 || lockupEndTimestamp != 0) {
                vestingWallet.setLockupPeriod(lockupStartTimestamp, lockupEndTimestamp);
                console.log("Lockup period set from ", lockupStartTimestamp, " to ", lockupEndTimestamp);
            }

            vestingWallet.transferOwnership(finalOwner);
            console.log("Transferred ownership to: ", finalOwner);
        }

        vm.stopBroadcast();
    }
}
