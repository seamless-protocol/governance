// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {StakedToken} from "../../src/StakedToken.sol";
import {Constants} from "../../src/library/Constants.sol";
import {SeamHarness} from "../harness/SeamHarness.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

contract StakedSeamUpgrade is Test {
    StakedToken stkToken = StakedToken(Constants.stkSEAM);
    StakedToken newImplementation;
    SeamHarness seam = SeamHarness(Constants.SEAM_ADDRESS);

    bytes32 constant ERC1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 27559800);
        newImplementation = new StakedToken();

        vm.startPrank(Constants.LONG_TIMELOCK_ADDRESS);
        seam.upgradeToAndCall(address(new SeamHarness()), "");
        vm.stopPrank();
    }

    function test_Upgrade() public {
        address implementationBefore =
            address(uint160(uint256(vm.load(address(stkToken), ERC1967_IMPLEMENTATION_SLOT))));

        assertNotEq(implementationBefore, address(newImplementation));

        _upgradeStakedToken();

        address implementationAfter = address(uint160(uint256(vm.load(address(stkToken), ERC1967_IMPLEMENTATION_SLOT))));

        assertEq(implementationAfter, address(newImplementation));
    }

    function test_GetVotes() public {
        address user = makeAddr("user");
        uint256 amount = 1000e18;

        uint256 totalSupplyBefore = stkToken.totalSupply();
        uint256 assetBalanceBefore = stkToken.totalAssets();

        seam.exposed_mint(address(stkToken), amount);
        seam.exposed_mint(user, amount);

        vm.startPrank(user);
        seam.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);
        stkToken.delegate(user);
        vm.stopPrank();

        uint256 stkTokenBalance = stkToken.balanceOf(user);

        assertNotEq(stkToken.getVotes(user), amount);
        assertEq(stkToken.getVotes(user), stkTokenBalance);

        _upgradeStakedToken();

        assertEq(stkToken.getVotes(user), 0);

        vm.prank(user);
        stkToken.deposit(0, user);

        assertEq(
            stkToken.getVotes(user),
            stkTokenBalance * (assetBalanceBefore + amount * 2) / (totalSupplyBefore + stkTokenBalance)
        );
    }

    function _upgradeStakedToken() internal {
        vm.prank(Constants.SHORT_TIMELOCK_ADDRESS);
        stkToken.upgradeToAndCall(address(newImplementation), "");
    }
}
