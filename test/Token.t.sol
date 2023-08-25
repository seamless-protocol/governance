// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

contract TokenTest is Test {
    Token public token;

    function setUp() public {
        token = new Token();
    }

    function testDeployed() public {
        assertEq(token.name(), "Seamless");
        assertEq(token.symbol(), "SEAM");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 100_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), token.balanceOf(address(this)));
    }
}
