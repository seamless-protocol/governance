// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../src/Seam.sol";
import {Constants} from "../src/library/Constants.sol";

contract SeamDeployScript is Script {
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

        Seam tokenImplementation = new Seam();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(tokenImplementation),
            abi.encodeWithSelector(
                Seam.initialize.selector,
                Constants.TOKEN_NAME,
                Constants.TOKEN_SYMBOL,
                Constants.MINT_AMOUNT * (10 ** tokenImplementation.decimals())
            )
        );

        console.log("Deployed token proxy to: ", address(proxy), " implementation: ", address(tokenImplementation));

        Seam tokenProxy = Seam(address(proxy));

        address transferRolesTo = Constants.TRANSFER_ROLES_TO;
        if (transferRolesTo != address(0)) {
            tokenProxy.grantRole(tokenProxy.DEFAULT_ADMIN_ROLE(), transferRolesTo);
            console.log("Role: DEFAULT_ADMIN_ROLE granted to: ", transferRolesTo);
            tokenProxy.grantRole(tokenProxy.UPGRADER_ROLE(), transferRolesTo);
            console.log("Role: UPGRADER_ROLE granted to: ", transferRolesTo);
        }

        if (Constants.REVOKE_DEPLOYER_PERM) {
            tokenProxy.revokeRole(tokenProxy.UPGRADER_ROLE(), deployerAddress);
            console.log("Role: UPGRADER_ROLE revoked from: ", deployerAddress);
            tokenProxy.revokeRole(tokenProxy.DEFAULT_ADMIN_ROLE(), deployerAddress);
            console.log("Role: DEFAULT_ADMIN_ROLE revoked from: ", deployerAddress);
        }

        vm.stopBroadcast();
    }
}
