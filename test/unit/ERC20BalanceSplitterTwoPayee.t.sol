// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20BalanceSplitterTwoPayee} from "src/ERC20BalanceSplitterTwoPayee.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";

contract ERC20BalanceSplitterTwoPayeeTest is Test {
    ERC20BalanceSplitterTwoPayee public splitter;
    ERC20Mock public token;

    address _alice;
    address _bob;

    function setUp() public {
        _alice = makeAddr("alice");
        _bob = makeAddr("bob");

        token = new ERC20Mock();
    }

    function test_constructor() public {
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, token, 5000);

        assertEq(splitter.payeeA(), _alice);
        assertEq(splitter.payeeB(), _bob);
        assertEq(address(splitter.token()), address(token));
        assertEq(splitter.shareA(), 5000);
    }

    function test_claim() public {
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, token, 5000);

        // Mint tokens to splitter
        token.mint(address(splitter), 100e18);

        // Check initial balances
        assertEq(token.balanceOf(address(splitter)), 100e18);
        assertEq(token.balanceOf(_alice), 0);
        assertEq(token.balanceOf(_bob), 0);

        // Claim and verify split
        splitter.claim();

        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(_alice), 50e18); // 50% of 100
        assertEq(token.balanceOf(_bob), 50e18); // 50% of 100
    }

    function test_claim_uneven_split() public {
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, token, 7000);

        // Mint tokens to splitter
        token.mint(address(splitter), 100e18);

        // Claim and verify 70/30 split
        splitter.claim();

        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(_alice), 70e18); // 70% of 100
        assertEq(token.balanceOf(_bob), 30e18); // 30% of 100
    }

    function test_claim_zero_balance() public {
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, token, 5000);

        // Claim with zero balance should not revert
        splitter.claim();

        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(token.balanceOf(_alice), 0);
        assertEq(token.balanceOf(_bob), 0);
    }

    function test_skim() public {
        ERC20Mock otherToken = new ERC20Mock();
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, token, 5000);

        // Mint other token to splitter
        otherToken.mint(address(splitter), 100e18);

        // Check initial balances
        assertEq(otherToken.balanceOf(address(splitter)), 100e18);
        assertEq(otherToken.balanceOf(_alice), 0);

        // Skim and verify
        splitter.skim(otherToken);

        assertEq(otherToken.balanceOf(address(splitter)), 0);
        assertEq(otherToken.balanceOf(_alice), 100e18);
    }

    function test_revert_invalid_share() public {
        vm.expectRevert(abi.encodeWithSelector(ERC20BalanceSplitterTwoPayee.InvalidShare.selector, 10001));
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, token, 10001);
    }

    function test_revert_zero_address() public {
        vm.expectRevert(ERC20BalanceSplitterTwoPayee.ZeroAddress.selector);
        splitter = new ERC20BalanceSplitterTwoPayee(address(0), _bob, token, 5000);

        vm.expectRevert(ERC20BalanceSplitterTwoPayee.ZeroAddress.selector);
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, address(0), token, 5000);
    }

    function test_revert_invalid_token() public {
        vm.expectRevert(ERC20BalanceSplitterTwoPayee.InvalidToken.selector);
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, IERC20(address(0)), 5000);
    }

    function test_revert_same_addresses() public {
        vm.expectRevert(ERC20BalanceSplitterTwoPayee.SameAddresses.selector);
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _alice, token, 5000);
    }

    function test_revert_skim_invalid_token() public {
        splitter = new ERC20BalanceSplitterTwoPayee(_alice, _bob, token, 5000);

        vm.expectRevert(ERC20BalanceSplitterTwoPayee.InvalidToken.selector);
        splitter.skim(IERC20(address(0)));

        vm.expectRevert(ERC20BalanceSplitterTwoPayee.InvalidToken.selector);
        splitter.skim(token);
    }
}
