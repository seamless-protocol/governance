// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "src/Seam.sol";
import {EscrowSeam} from "src/EscrowSeam.sol";
import {Depositor} from "./helpers/Depositor.sol";

contract EscrowSeamTest is Test {
    uint256 public ROUNDING_TOLERANCE = 10;
    uint256 public constant VESTING_DURATION = 365 days;

    Depositor public user;

    Seam public seam;
    EscrowSeam public esSEAM;

    function setUp() public {
        Seam tokenImplementation = new Seam();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(tokenImplementation),
            abi.encodeWithSelector(
                Seam.initialize.selector,
                "Seamless",
                "SEAM",
                100_000_000 ether
            )
        );
        seam = Seam(address(proxy));

        EscrowSeam implementation = new EscrowSeam();
        proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                EscrowSeam.initialize.selector,
                address(seam),
                VESTING_DURATION,
                address(this)
            )
        );
        esSEAM = EscrowSeam(address(proxy));
        user = new Depositor(address(esSEAM));
        esSEAM.grantRole(esSEAM.DEPOSITOR_ROLE(), address(user));

        seam.transfer(address(esSEAM), 100_000_000 ether);
    }

    function testDeploy() public {
        assertEq(esSEAM.vestingDuration(), VESTING_DURATION);
        assertTrue(esSEAM.hasRole(esSEAM.DEPOSITOR_ROLE(), address(user)));
        assertTrue(esSEAM.hasRole(esSEAM.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function testSimpleDeposit() public {
        uint256 depositAmount = 1000 ether;
        user.deposit(depositAmount);

        (uint256 claimableAmount,, uint256 vestingEndsAt, uint256 lastUpdatedTimestamp) =
            esSEAM.vestingInfo(address(user));
        assertEq(claimableAmount, 0);
        assertEq(vestingEndsAt, block.timestamp + VESTING_DURATION);
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertEq(esSEAM.balanceOf(address(user)), depositAmount);
    }

    function testMultipleDeposits() public {
        uint256 depositAmount1 = 1000 ether;
        user.deposit(depositAmount1);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 depositAmount2 = 1500 ether;
        user.deposit(depositAmount2);

        //Now half of first deposit shoudl be unvested
        //Now user should have 2000 tokens vested on 10,5 months
        uint256 correctUnvestedAmount = depositAmount1 / 2;
        uint256 correctNewVestingPeriod = (VESTING_DURATION * 21) / 24;
        (uint256 claimableAmount,, uint256 vestingEndsAt, uint256 lastUpdatedTimestamp) =
            esSEAM.vestingInfo(address(user));

        assertApproxEqAbs(claimableAmount, depositAmount1 / 2, ROUNDING_TOLERANCE);
        assertApproxEqAbs(vestingEndsAt, block.timestamp + correctNewVestingPeriod, ROUNDING_TOLERANCE);
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertEq(esSEAM.balanceOf(address(user)), depositAmount1 + depositAmount2);

        vm.warp(block.timestamp + correctNewVestingPeriod / 5); // Increase for 2,1 months
        //Now 20% of 2000 tokens should be unvested
        //Now user has 1600 tokens vested on 8,4 months

        uint256 depositAmount3 = 1600 ether;
        user.deposit(depositAmount3);
        //After this deposit user should have 3200 tokens vested
        //Vesting period should be (12 + 8,4) / 2 = 10,2 months

        correctUnvestedAmount += (depositAmount1 + depositAmount2 - correctUnvestedAmount) / 5;
        correctNewVestingPeriod = (VESTING_DURATION * 102) / 120;
        (claimableAmount,, vestingEndsAt, lastUpdatedTimestamp) = esSEAM.vestingInfo(address(user));

        assertApproxEqAbs(claimableAmount, correctUnvestedAmount, ROUNDING_TOLERANCE);
        assertApproxEqAbs(vestingEndsAt, block.timestamp + correctNewVestingPeriod, ROUNDING_TOLERANCE);
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertEq(esSEAM.balanceOf(address(user)), depositAmount1 + depositAmount2 + depositAmount3);

        //Increase time by 12 months
        //User should now have 3200 tokens unvester and 0 tokens unvested
        vm.warp(block.timestamp + VESTING_DURATION);

        uint256 depositAmount4 = 1000 ether;
        user.deposit(depositAmount4);

        correctUnvestedAmount += 3200 ether;
        (claimableAmount,, vestingEndsAt, lastUpdatedTimestamp) = esSEAM.vestingInfo(address(user));

        assertApproxEqAbs(claimableAmount, correctUnvestedAmount, ROUNDING_TOLERANCE);
        assertEq(vestingEndsAt, block.timestamp + VESTING_DURATION);
        assertEq(lastUpdatedTimestamp, block.timestamp);

        user.claim();

        // After this warp user should have 500 tokens unvested and 500 tokens vested for 6 months
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 seamBalanceBefore = seam.balanceOf(address(user));
        uint256 esSEAMBalanceBefore = esSEAM.balanceOf(address(user));

        user.claim();

        (claimableAmount,, vestingEndsAt, lastUpdatedTimestamp) = esSEAM.vestingInfo(address(user));
        assertApproxEqAbs(claimableAmount, 0, ROUNDING_TOLERANCE);
        assertEq(vestingEndsAt, block.timestamp + VESTING_DURATION / 2);
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertApproxEqAbs(seam.balanceOf(address(user)), seamBalanceBefore + 500 ether, ROUNDING_TOLERANCE);
        assertApproxEqAbs(esSEAM.balanceOf(address(user)), esSEAMBalanceBefore - 500 ether, ROUNDING_TOLERANCE);
    }

    function testClaimMultipleDepositsAndClaims() public {
        uint256 depositAmount1 = 1000 ether;
        user.deposit(depositAmount1);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        uint256 depositAmount2 = 1500 ether;
        user.deposit(depositAmount2);

        //Now half of first deposit shoudl be unvested
        //Now user should have 2000 tokens vested on 10,5 months
        uint256 correctNewVestingPeriod = (VESTING_DURATION * 21) / 24;
        vm.warp(block.timestamp + correctNewVestingPeriod / 5); // Increase for 2,1 months
        //Now 20% of 2000 tokens should be unvested
        //Now user has 1600 tokens vested on 8,4 months

        //After this deposit user should have 3200 tokens vested
        //Vesting period should be (12 + 8,4) / 2 = 10,2 months
        uint256 depositAmount3 = 1600 ether;
        user.deposit(depositAmount3);

        (uint256 claimableAmount,,,) = esSEAM.vestingInfo(address(user));
        uint256 esSEAMBalanceBefore = esSEAM.balanceOf(address(user));

        user.claim();

        assertEq(seam.balanceOf(address(user)), claimableAmount);
        assertEq(esSEAM.balanceOf(address(user)), esSEAMBalanceBefore - claimableAmount);
        (claimableAmount,,,) = esSEAM.vestingInfo(address(user));
        assertEq(claimableAmount, 0);

        //Increase time by 5,1 months
        //User should now have 1600 tokens vester and 1600 tokens unvested
        vm.warp(block.timestamp + (VESTING_DURATION * 51) / 120);

        uint256 seamBalanceBefore = seam.balanceOf(address(user));
        esSEAMBalanceBefore = esSEAM.balanceOf(address(user));

        user.claim();

        assertApproxEqAbs(seam.balanceOf(address(user)), seamBalanceBefore + 1600 ether, ROUNDING_TOLERANCE);
        assertApproxEqAbs(esSEAM.balanceOf(address(user)), esSEAMBalanceBefore - 1600 ether, ROUNDING_TOLERANCE);

        //Increase time by 6 months
        //User should now have 1600 tokens unvested and 0 tokens unvested
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        seamBalanceBefore = seam.balanceOf(address(user));
        esSEAMBalanceBefore = esSEAM.balanceOf(address(user));

        user.claim();

        assertApproxEqAbs(seam.balanceOf(address(user)), seamBalanceBefore + 1600 ether, ROUNDING_TOLERANCE);
        assertApproxEqAbs(esSEAM.balanceOf(address(user)), 0, ROUNDING_TOLERANCE);
    }
}
