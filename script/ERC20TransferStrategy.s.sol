// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20TransferStrategy} from "../src/transfer-strategies/ERC20TransferStrategy.sol";
import {Constants} from "../src/library/Constants.sol";

contract ERC20TransferStrategyScript is Script {
    IERC20 constant rewardToken = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        ERC20TransferStrategy strategy = new ERC20TransferStrategy(
            rewardToken, Constants.INCENTIVES_CONTROLLER_ADDRESS, Constants.SHORT_TIMELOCK_ADDRESS
        );
        console.log(
            "ERC20 transfer strategy deployed to: %s, reward token: %s", address(strategy), address(rewardToken)
        );

        vm.stopBroadcast();
    }
}
