// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Seam, Initializable} from "../src/Seam.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

contract SeamTest is Test {
    Seam public tokenImplementation;
    Seam public tokenProxy;

    address immutable _alice = makeAddr("alice");

    function setUp() public {
        tokenImplementation = new Seam();
        ERC1967Proxy proxy =
        new ERC1967Proxy(address(tokenImplementation), abi.encodeWithSelector(Seam.initialize.selector, "test token name", "test token symbol", 100));
        tokenProxy = Seam(address(proxy));
    }

    function test_Deployed() public {
        assertEq(tokenProxy.name(), "test token name");
        assertEq(tokenProxy.symbol(), "test token symbol");
        assertEq(tokenProxy.decimals(), 18);
        assertEq(tokenProxy.totalSupply(), 100);
        assertEq(tokenProxy.hasRole(tokenProxy.DEFAULT_ADMIN_ROLE(), address(this)), true);
        assertEq(tokenProxy.hasRole(tokenProxy.UPGRADER_ROLE(), address(this)), true);
    }

    function test_Upgrade() public {
        address newImplementation = address(new Seam());

        tokenProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        vm.startPrank(_alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, _alice, tokenProxy.UPGRADER_ROLE()
            )
        );
        tokenProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        vm.stopPrank();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        tokenProxy.upgradeToAndCall(
            address(newImplementation),
            abi.encodeWithSelector(Seam.initialize.selector, "test token name", "test token symbol", 100)
        );
    }
}
