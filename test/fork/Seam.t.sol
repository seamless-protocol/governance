// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../../src/Seam.sol";
import {SeamGovernor} from "../../src/SeamGovernor.sol";
import {Constants} from "../../src/library/Constants.sol";

contract SeamForkTest is Test {
    Seam public proxy = Seam(Constants.SEAM_ADDRESS);
    SeamGovernor public governor = SeamGovernor(payable(Constants.GOVERNOR_SHORT_ADDRESS));

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 7567615);
    }

    function testUpgrade() public {
        address newImplementation = address(new Seam());
        uint8 decimals = proxy.decimals();

        assertEq(proxy.getPastTotalSupply(block.timestamp - 1), 0);
        assertEq(proxy.totalSupply(), 100_000_000 * (10 ** decimals));
        assertEq(governor.quorum(block.timestamp - 1), 0);

        vm.prank(Constants.GUARDIAN_WALLET);
        proxy.upgradeToAndCall(address(newImplementation), abi.encodeWithSelector(Seam.initializeV2.selector));

        vm.warp(block.timestamp + 1);

        assertEq(proxy.getPastTotalSupply(block.timestamp - 1), 100_000_000 * (10 ** decimals));
        assertEq(proxy.totalSupply(), 100_000_000 * (10 ** decimals));
        assertEq(governor.quorum(block.timestamp - 1), 1_500_000 * (10 ** decimals));
    }
}
