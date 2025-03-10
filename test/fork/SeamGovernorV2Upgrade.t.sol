// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakedToken} from "../../src/StakedToken.sol";
import {Seam} from "../../src/Seam.sol";
import {SeamGovernor} from "../../src/SeamGovernor.sol";
import {SeamGovernorV2} from "../../src/SeamGovernorV2.sol";
import {Constants} from "../../src/library/Constants.sol";
import {SeamHarness} from "../harness/SeamHarness.sol";
import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";

contract SeamGovernorV2Upgrade is Test {
    SeamHarness seam = SeamHarness(Constants.SEAM_ADDRESS);
    SeamGovernor governorShortProxy = SeamGovernor(payable(Constants.GOVERNOR_SHORT_ADDRESS));
    SeamGovernor governorLongProxy = SeamGovernor(payable(Constants.GOVERNOR_LONG_ADDRESS));

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 25444678);

        SeamHarness seamHarness = new SeamHarness();

        vm.prank(Constants.LONG_TIMELOCK_ADDRESS);
        seam.upgradeToAndCall(address(seamHarness), "");
    }

    function test_Upgrade(uint256 seamAmount, uint256 stakeAmount, uint256 unstakeAmount) public {
        seamAmount = bound(seamAmount, 2, (type(uint208).max - seam.totalSupply()) - 2);
        stakeAmount = bound(stakeAmount, 1, seamAmount - 1);
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);

        StakedToken stkSEAM = _deployStakedSEAM();

        address user1 = makeAddr("user1");

        seam.exposed_mint(user1, seamAmount);

        vm.startPrank(user1);

        seam.delegate(user1);

        seam.approve(address(stkSEAM), stakeAmount);
        stkSEAM.deposit(stakeAmount, user1);
        stkSEAM.delegate(user1);

        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        // Check that stkSEAM delegation is not counted before upgrade
        assertEq(governorShortProxy.getVotes(user1, block.timestamp - 1), seamAmount - stakeAmount);
        assertEq(governorLongProxy.getVotes(user1, block.timestamp - 1), seamAmount - stakeAmount);

        SeamGovernorV2 newImplementation = new SeamGovernorV2();

        vm.startPrank(Constants.LONG_TIMELOCK_ADDRESS);

        governorShortProxy.upgradeToAndCall(
            address(newImplementation), abi.encodeWithSelector(SeamGovernorV2.initializeV2.selector, stkSEAM)
        );
        governorLongProxy.upgradeToAndCall(
            address(newImplementation), abi.encodeWithSelector(SeamGovernorV2.initializeV2.selector, stkSEAM)
        );

        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        // Check that stkSEAM delegation is counted after upgrade
        assertEq(governorShortProxy.getVotes(user1, block.timestamp - 1), seamAmount);
        assertEq(governorLongProxy.getVotes(user1, block.timestamp - 1), seamAmount);

        IERC5805[] memory shortTokens = SeamGovernorV2(payable(address(governorShortProxy))).tokens();
        IERC5805[] memory longTokens = SeamGovernorV2(payable(address(governorLongProxy))).tokens();

        assertEq(shortTokens.length, 3);
        assertEq(longTokens.length, 3);

        assertEq(address(shortTokens[0]), address(Constants.SEAM_ADDRESS));
        assertEq(address(shortTokens[1]), address(Constants.ESCROW_SEAM_ADDRESS));
        assertEq(address(shortTokens[2]), address(stkSEAM));

        assertEq(address(longTokens[0]), address(Constants.SEAM_ADDRESS));
        assertEq(address(longTokens[1]), address(Constants.ESCROW_SEAM_ADDRESS));
        assertEq(address(longTokens[2]), address(stkSEAM));

        address user2 = makeAddr("user2");

        vm.startPrank(user1);

        stkSEAM.cooldown();

        vm.warp(block.timestamp + 7 days + 1);

        stkSEAM.redeem(unstakeAmount, user2, user1);

        vm.stopPrank();

        vm.prank(user2);
        seam.delegate(user2);

        vm.warp(block.timestamp + 1);

        assertEq(governorShortProxy.getVotes(user1, block.timestamp - 1), seamAmount - unstakeAmount);
        assertEq(governorLongProxy.getVotes(user1, block.timestamp - 1), seamAmount - unstakeAmount);

        assertEq(governorShortProxy.getVotes(user2, block.timestamp - 1), unstakeAmount);
        assertEq(governorLongProxy.getVotes(user2, block.timestamp - 1), unstakeAmount);
    }

    function _deployStakedSEAM() internal returns (StakedToken) {
        StakedToken implementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                Constants.SEAM_ADDRESS,
                address(this),
                "TEST", // "stakedSEAM",
                "TST", // "stkSEAM",
                7 days,
                1 days
            )
        );

        return StakedToken(address(proxy));
    }
}
