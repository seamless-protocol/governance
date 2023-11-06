// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {EscrowSeam} from "src/EscrowSeam.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EscrowSeamDeployer {
    function deployEscrowSeam(address seam, uint256 vestingDuration, address admin) public returns (EscrowSeam) {
        EscrowSeam implementation = new EscrowSeam();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                EscrowSeam.initialize.selector,
                seam,
                vestingDuration,
                admin
            )
        );
        console.log("EscrowSeamProxy deployed to: ", address(proxy), " implementation: ", address(implementation));

        return EscrowSeam(address(proxy));
    }
}
