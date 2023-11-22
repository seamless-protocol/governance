// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamVestingWallet} from "../src/SeamVestingWallet.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamVestingWalletDeployScript is Script {
    error BenefiaryRequired();

    address constant INITIAL_OWNER = address(0);
    address constant BENEFICIARY = address(0);
    IERC20 constant TOKEN = IERC20(Constants.SEAM_ADDRESS);
    uint64 constant DURATION_SECONDS = 3 * (365 * 24 * 60 * 60); // 3 years

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

        if (BENEFICIARY == address(0)) {
            revert BenefiaryRequired();
        }

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
                INITIAL_OWNER == address(0) ? deployerAddress : INITIAL_OWNER,
                BENEFICIARY,
                TOKEN,
                DURATION_SECONDS
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
