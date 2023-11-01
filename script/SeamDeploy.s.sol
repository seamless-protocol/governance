// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../src/Seam.sol";

contract SeamDeployScript is Script {
    string constant TOKEN_NAME = "Seamless";
    string constant TOKEN_SYMBOL = "SEAM";
    uint256 constant MINT_AMOUNT = 100_000_000;
    address constant TRANSFER_ROLES_TO = 0xA1b5f2cc9B407177CD8a4ACF1699fa0b99955A22;
    bool constant REVOKE_DEPLOYER_PERM = true;

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
                TOKEN_NAME,
                TOKEN_SYMBOL,
                MINT_AMOUNT * (10 ** tokenImplementation.decimals())
            )
        );

        console.log("Deployed token proxy to: ", address(proxy), " implementation: ", address(tokenImplementation));

        Seam tokenProxy = Seam(address(proxy));

        if (TRANSFER_ROLES_TO != address(0)) {
            tokenProxy.grantRole(tokenProxy.DEFAULT_ADMIN_ROLE(), TRANSFER_ROLES_TO);
            console.log("Role: DEFAULT_ADMIN_ROLE granted to: ", TRANSFER_ROLES_TO);
            tokenProxy.grantRole(tokenProxy.UPGRADER_ROLE(), TRANSFER_ROLES_TO);
            console.log("Role: UPGRADER_ROLE granted to: ", TRANSFER_ROLES_TO);
        }

        if (REVOKE_DEPLOYER_PERM) {
            tokenProxy.revokeRole(tokenProxy.UPGRADER_ROLE(), deployerAddress);
            console.log("Role: UPGRADER_ROLE revoked from: ", deployerAddress);
            tokenProxy.revokeRole(tokenProxy.DEFAULT_ADMIN_ROLE(), deployerAddress);
            console.log("Role: DEFAULT_ADMIN_ROLE revoked from: ", deployerAddress);
        }

        vm.stopBroadcast();
    }
}
