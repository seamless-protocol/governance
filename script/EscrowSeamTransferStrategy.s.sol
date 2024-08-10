// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IEscrowSeam} from "../src/interfaces/IEscrowSeam.sol";
import {EscrowSeamTransferStrategy} from "../src/transfer-strategies/EscrowSeamTransferStrategy.sol";
import {Constants} from "../src/library/Constants.sol";

contract EscrowSeamTransferStrategyScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        EscrowSeamTransferStrategy strategy = new EscrowSeamTransferStrategy(
            IERC20(Constants.SEAM_ADDRESS),
            IEscrowSeam(Constants.ESCROW_SEAM_ADDRESS),
            Constants.INCENTIVES_CONTROLLER_ADDRESS,
            Constants.SHORT_TIMELOCK_ADDRESS
        );
        console.log("EscrowSeam transfer strategy deployed to: ", address(strategy));

        vm.stopBroadcast();
    }
}
