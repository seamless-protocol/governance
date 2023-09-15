// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {SeamToken} from "../src/SeamToken.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

contract SeamTokenTest is Test {
    SeamToken public tokenImplementation;
    SeamToken public tokenProxy;

    address constant TEST_ACCOUNT_1 = address(1);
    address constant TEST_ACCOUNT_2 = address(2);

    function setUp() public {
        tokenImplementation = new SeamToken();
        ERC1967Proxy proxy =
        new ERC1967Proxy(address(tokenImplementation), abi.encodeWithSelector(SeamToken.initialize.selector, "test token name", "test token symbol"));
        tokenProxy = SeamToken(address(proxy));
    }

    function test_Deployed() public {
        assertEq(tokenProxy.name(), "test token name");
        assertEq(tokenProxy.symbol(), "test token symbol");
        assertEq(tokenProxy.decimals(), 18);
        assertEq(tokenProxy.totalSupply(), 0);
        assertEq(tokenProxy.hasRole(tokenProxy.DEFAULT_ADMIN_ROLE(), address(this)), true);
        assertEq(tokenProxy.hasRole(tokenProxy.UPGRADER_ROLE(), address(this)), true);
    }

    function test_Upgrade() public {
        address newImplementation = address(new SeamToken());

        tokenProxy.upgradeTo(newImplementation);

        vm.startPrank(TEST_ACCOUNT_2);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(TEST_ACCOUNT_2),
                " is missing role ",
                Strings.toHexString(uint256(tokenProxy.UPGRADER_ROLE()), 32)
            )
        );
        tokenProxy.upgradeTo(address(newImplementation));
    }

    function test_Mint_Burn() public {
        uint256 amount = 1;
        tokenProxy.mint(TEST_ACCOUNT_1, amount);

        assertEq(tokenProxy.totalSupply(), amount);
        assertEq(tokenProxy.balanceOf(TEST_ACCOUNT_1), amount);

        tokenProxy.burn(TEST_ACCOUNT_1, amount);

        assertEq(tokenProxy.totalSupply(), 0);
        assertEq(tokenProxy.balanceOf(TEST_ACCOUNT_1), 0);

        vm.startPrank(TEST_ACCOUNT_2);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(TEST_ACCOUNT_2),
                " is missing role ",
                Strings.toHexString(uint256(tokenProxy.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        tokenProxy.mint(TEST_ACCOUNT_1, amount);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(TEST_ACCOUNT_2),
                " is missing role ",
                Strings.toHexString(uint256(tokenProxy.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        tokenProxy.burn(TEST_ACCOUNT_1, amount);
    }
}
