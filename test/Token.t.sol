// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

contract TokenTest is Test {
    Token public tokenImplementation;
    Token public token;

    address constant TEST_ACCOUNT_1 = address(1);
    address constant TEST_ACCOUNT_2 = address(2);

    function setUp() public {
        tokenImplementation = new Token();
        ERC1967Proxy proxy =
        new ERC1967Proxy(address(tokenImplementation), abi.encodeWithSelector(Token.initialize.selector, "test token name", "test token symbol"));
        token = Token(address(proxy));
    }

    function test_Deployed() public {
        assertEq(token.name(), "test token name");
        assertEq(token.symbol(), "test token symbol");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.hasRole(token.DEFAULT_ADMIN_ROLE(), address(this)), true);
        assertEq(token.hasRole(token.UPGRADER_ROLE(), address(this)), true);
        assertEq(token.hasRole(token.MINTER_ROLE(), address(this)), true);
        assertEq(token.hasRole(token.TRANSFER_ROLE(), address(this)), true);
    }

    function test_Upgrade() public {
        address newImplementation = address(new Token());

        token.upgradeTo(newImplementation);

        vm.startPrank(TEST_ACCOUNT_2);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(TEST_ACCOUNT_2),
                " is missing role ",
                Strings.toHexString(uint256(token.UPGRADER_ROLE()), 32)
            )
        );
        token.upgradeTo(address(token));
    }

    function test_Mint_Burn() public {
        uint256 amount = 1;
        token.mint(TEST_ACCOUNT_1, amount);

        assertEq(token.totalSupply(), amount);
        assertEq(token.balanceOf(TEST_ACCOUNT_1), amount);

        token.burn(TEST_ACCOUNT_1, amount);

        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(TEST_ACCOUNT_1), 0);

        vm.startPrank(TEST_ACCOUNT_2);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(TEST_ACCOUNT_2),
                " is missing role ",
                Strings.toHexString(uint256(token.MINTER_ROLE()), 32)
            )
        );
        token.mint(TEST_ACCOUNT_1, amount);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(TEST_ACCOUNT_2),
                " is missing role ",
                Strings.toHexString(uint256(token.MINTER_ROLE()), 32)
            )
        );
        token.burn(TEST_ACCOUNT_1, amount);
    }

    function test_Transfer() public {
        uint256 amount = 1;

        token.mint(address(this), amount);
        token.transfer(TEST_ACCOUNT_1, amount);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(TEST_ACCOUNT_1), amount);

        vm.startPrank(TEST_ACCOUNT_1);

        token.transfer(address(this), amount);

        assertEq(token.balanceOf(address(this)), amount);
        assertEq(token.balanceOf(TEST_ACCOUNT_1), 0);

        vm.expectRevert("ERC20: token is not transferable");
        token.transfer(TEST_ACCOUNT_2, amount);
    }
}
