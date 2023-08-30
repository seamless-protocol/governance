// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Token} from "../src/Token.sol";

contract TokenDeployScript is Script {
    string constant TOKEN_NAME = "OG Points";
    string constant TOKEN_SYMBOL = "OG Points";
    uint256 constant MINT_AMOUNT = 15_000_000;
    address constant MINT_DESTINATION = address(0);
    address constant TRANSFER_ROLES_TO = address(0);
    bool constant REVOKE_DEPLOYER_PERM = false;

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

        Token tokenImplementation = new Token();
        ERC1967Proxy proxy =
        new ERC1967Proxy(address(tokenImplementation), abi.encodeWithSelector(Token.initialize.selector, TOKEN_NAME, TOKEN_SYMBOL));

        console.log("Deployed token proxy to: ", address(proxy), " implementation: ", address(tokenImplementation));

        Token tokenProxy = Token(address(proxy));

        if (MINT_AMOUNT > 0 && MINT_DESTINATION != address(0)) {
            tokenProxy.mint(MINT_DESTINATION, MINT_AMOUNT * (10 ** tokenProxy.decimals()));
            console.log("Minted amount: ", MINT_AMOUNT, " to: ", MINT_DESTINATION);
        }

        if (TRANSFER_ROLES_TO != address(0)) {
            tokenProxy.grantRole(tokenProxy.DEFAULT_ADMIN_ROLE(), TRANSFER_ROLES_TO);
            console.log("Role: DEFAULT_ADMIN_ROLE granted to: ", TRANSFER_ROLES_TO);
            tokenProxy.grantRole(tokenProxy.UPGRADER_ROLE(), TRANSFER_ROLES_TO);
            console.log("Role: UPGRADER_ROLE granted to: ", TRANSFER_ROLES_TO);
            tokenProxy.grantRole(tokenProxy.MINTER_ROLE(), TRANSFER_ROLES_TO);
            console.log("Role: MINTER_ROLE granted to: ", TRANSFER_ROLES_TO);
            tokenProxy.grantRole(tokenProxy.TRANSFER_ROLE(), TRANSFER_ROLES_TO);
            console.log("Role: TRANSFER_ROLE granted to: ", TRANSFER_ROLES_TO);
        }

        if (REVOKE_DEPLOYER_PERM) {
            tokenProxy.revokeRole(tokenProxy.UPGRADER_ROLE(), deployerAddress);
            console.log("Role: UPGRADER_ROLE revoked from: ", deployerAddress);
            tokenProxy.revokeRole(tokenProxy.MINTER_ROLE(), deployerAddress);
            console.log("Role: MINTER_ROLE revoked from: ", deployerAddress);
            tokenProxy.revokeRole(tokenProxy.TRANSFER_ROLE(), deployerAddress);
            console.log("Role: TRANSFER_ROLE revoked from: ", deployerAddress);
            tokenProxy.revokeRole(tokenProxy.DEFAULT_ADMIN_ROLE(), deployerAddress);
            console.log("Role: DEFAULT_ADMIN_ROLE revoked from: ", deployerAddress);
        }

        vm.stopBroadcast();
    }
}
