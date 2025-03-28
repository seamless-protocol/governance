// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SeamVestingWalletV2} from "../../src/SeamVestingWalletV2.sol";
import {ISeamVestingWalletV2} from "../../src/interfaces/ISeamVestingWalletV2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {StakedToken} from "../../src/StakedToken.sol";
import {Constants} from "../../src/library/Constants.sol";

contract SeamVestingWalletV2ForkTest is Test {
    SeamVestingWalletV2 implementation;
    SeamVestingWalletV2 proxy;
    IERC20 seam;
    StakedToken stkSeam;

    address owner;
    address beneficiary;

    uint64 constant MAX_DURATION = 1460 days; // 4 years
    uint64 constant MIN_DURATION = 30 days;
    uint64 constant MAX_CLIFF = 365 days;

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 28203830);

        owner = makeAddr("owner");
        beneficiary = makeAddr("beneficiary");
        seam = IERC20(Constants.SEAM_ADDRESS);
        stkSeam = StakedToken(Constants.stkSEAM);

        implementation = new SeamVestingWalletV2();
    }

    function testFuzz_Fork_VestingCycle(
        uint64 vestingDuration,
        uint64 vestingCliff,
        uint256 vestingAmount,
        uint64 timeElapsed
    ) public {
        // Bound inputs to reasonable values
        vestingDuration = uint64(bound(vestingDuration, MIN_DURATION, MAX_DURATION));
        vestingCliff = uint64(bound(vestingCliff, 0, vestingDuration));
        vestingAmount = bound(vestingAmount, 1000e18, 10_000_000e18); // 1K to 10M SEAM
        timeElapsed = uint64(bound(timeElapsed, vestingCliff, vestingDuration));

        _deployProxy(uint256(block.timestamp), vestingDuration, vestingCliff);
        deal(address(seam), address(proxy), vestingAmount);

        // Move past cliff
        vm.warp(block.timestamp + timeElapsed);

        // Calculate expected vested amount
        uint256 expectedVested = (vestingAmount * timeElapsed) / vestingDuration;
        assertApproxEqRel(proxy.vestedAmount(uint64(block.timestamp)), expectedVested, 0.01e18);

        // Release tokens
        uint256 balanceBefore = seam.balanceOf(beneficiary);
        vm.prank(beneficiary);
        proxy.release();
        assertEq(seam.balanceOf(beneficiary) - balanceBefore, expectedVested);
    }

    function testFuzz_Fork_StakeWithVotingPower(uint64 vestingDuration, uint256 vestingAmount, uint256 stakePercent)
        public
    {
        vestingDuration = uint64(bound(vestingDuration, MIN_DURATION, MAX_DURATION));
        vestingAmount = bound(vestingAmount, 1000e18, 10_000_000e18);
        stakePercent = bound(stakePercent, 1, 100);

        _deployProxy(uint256(block.timestamp), vestingDuration, 0); // No cliff for simplicity
        deal(address(seam), address(proxy), vestingAmount);

        vm.warp(block.timestamp + vestingDuration / 2);

        // Calculate stake amount as percentage of vested tokens
        uint256 vestedAmount = proxy.vestedAmount(uint64(block.timestamp));
        uint256 stakeAmount = (vestedAmount * stakePercent) / 100;

        // Setup for staking
        vm.startPrank(beneficiary);
        seam.approve(address(proxy), stakeAmount);
        seam.transfer(address(proxy), stakeAmount);

        // Record initial voting power
        uint256 initialVotingPower = stkSeam.getVotes(address(proxy));

        // Stake tokens
        proxy.stake(stakeAmount);

        // Delegate to self to activate voting power
        proxy.delegate(address(stkSeam), address(proxy));

        // Verify increased voting power
        assertGt(stkSeam.getVotes(address(proxy)), initialVotingPower);

        vm.stopPrank();
    }

    function testFuzz_Fork_LockupOperations(uint64 vestingDuration, uint256 vestingAmount, uint64 lockupDuration)
        public
    {
        vestingDuration = uint64(bound(vestingDuration, MIN_DURATION, MAX_DURATION));
        vestingAmount = bound(vestingAmount, 1000e18, 10_000_000e18);
        lockupDuration = uint64(bound(lockupDuration, 1 days, 90 days));

        _deployProxy(uint256(block.timestamp), vestingDuration, 0);
        deal(address(seam), address(proxy), vestingAmount);

        // Move to 25% through vesting
        vm.warp(block.timestamp + vestingDuration / 4);

        // Stake some tokens before lockup
        uint256 stakeAmount = proxy.vestedAmount(uint64(block.timestamp)) / 2;
        vm.startPrank(beneficiary);
        seam.approve(address(proxy), stakeAmount);
        seam.transfer(address(proxy), stakeAmount);
        proxy.stake(stakeAmount);
        vm.stopPrank();

        // Set lockup period
        vm.prank(owner);
        proxy.setLockupPeriod(uint64(block.timestamp), uint64(block.timestamp + lockupDuration));

        // Verify operations during lockup
        vm.startPrank(beneficiary);

        // Should be able to stake during lockup
        uint256 additionalStake = proxy.vestedAmount(uint64(block.timestamp)) / 4;
        seam.approve(address(proxy), additionalStake);
        seam.transfer(address(proxy), additionalStake);
        proxy.stake(additionalStake);

        // Should be able to start cooldown during lockup
        proxy.cooldown();

        // Move past cooldown period but still in lockup
        vm.warp(block.timestamp + 7 days + 1);

        // Should be able to unstake during lockup
        proxy.unstake(stakeAmount);

        // Should be able to claim rewards during lockup
        proxy.claimAllStakedRewards(beneficiary);

        // But should not be able to release tokens
        vm.expectRevert(ISeamVestingWalletV2.LockupActive.selector);
        proxy.release();

        vm.stopPrank();

        // Move past lockup
        vm.warp(block.timestamp + lockupDuration + 1);

        // Should be able to release after lockup
        vm.prank(beneficiary);
        proxy.release();
    }

    function testFuzz_Fork_DelegateVotingPower(uint64 vestingDuration, uint256 vestingAmount, uint256 stakeAmount)
        public
    {
        vestingDuration = uint64(bound(vestingDuration, MIN_DURATION, MAX_DURATION));
        vestingAmount = bound(vestingAmount, 1000e18, 10_000_000e18);

        _deployProxy(uint256(block.timestamp), vestingDuration, 0);
        deal(address(seam), address(proxy), vestingAmount);

        vm.warp(block.timestamp + vestingDuration / 2);

        // Bound stake amount to available vested tokens
        stakeAmount = bound(stakeAmount, 1000e18, proxy.vestedAmount(uint64(block.timestamp)));

        // Setup for staking
        vm.startPrank(beneficiary);
        seam.approve(address(proxy), stakeAmount);
        seam.transfer(address(proxy), stakeAmount);
        proxy.stake(stakeAmount);

        // Create two delegatees
        address delegatee1 = makeAddr("delegatee1");
        address delegatee2 = makeAddr("delegatee2");

        // Record initial voting power
        uint256 initialVotingPower1 = stkSeam.getVotes(delegatee1);
        uint256 initialVotingPower2 = stkSeam.getVotes(delegatee2);

        // Delegate to first address
        proxy.delegate(address(stkSeam), delegatee1);
        assertEq(stkSeam.delegates(address(proxy)), delegatee1);
        assertGt(stkSeam.getVotes(delegatee1), initialVotingPower1);

        // Change delegation to second address
        proxy.delegate(address(stkSeam), delegatee2);
        assertEq(stkSeam.delegates(address(proxy)), delegatee2);
        assertGt(stkSeam.getVotes(delegatee2), initialVotingPower2);
        assertEq(stkSeam.getVotes(delegatee1), initialVotingPower1);

        vm.stopPrank();
    }

    function _deployProxy(uint256 vestingStart, uint64 vestingDuration, uint64 vestingCliff) internal {
        ERC1967Proxy proxy_ = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                SeamVestingWalletV2.initialize.selector,
                owner,
                beneficiary,
                seam,
                stkSeam,
                vestingStart,
                vestingDuration,
                vestingCliff
            )
        );
        proxy = SeamVestingWalletV2(address(proxy_));
    }
}
