// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SeamVestingWalletV2} from "../../src/SeamVestingWalletV2.sol";
import {ISeamVestingWalletV2} from "../../src/interfaces/ISeamVestingWalletV2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {StakedToken} from "../../src/StakedToken.sol";
import {FeeKeeper} from "../../src/FeeKeeper.sol";
import {ERC20TransferStrategy} from "../../src/transfer-strategies/ERC20TransferStrategy.sol";
import {Constants} from "../../src/library/Constants.sol";

contract SeamVestingWalletV2ForkTest is Test {
    SeamVestingWalletV2 implementation;
    SeamVestingWalletV2 proxy;
    IERC20 seam = IERC20(Constants.SEAM_ADDRESS);
    StakedToken stkSeam = StakedToken(Constants.stkSEAM);

    address owner = makeAddr("owner");
    address beneficiary = makeAddr("beneficiary");

    uint64 constant MAX_DURATION = 3650 days; // 10 years
    uint64 constant MIN_DURATION = 1 days;
    uint64 constant MAX_CLIFF = 365 days;

    uint256 constant MAX_VESTING_AMOUNT = 10_000_000e18;
    uint256 constant MIN_VESTING_AMOUNT = 1e18;

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 28203830);

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
        vestingAmount = bound(vestingAmount, MIN_VESTING_AMOUNT, MAX_VESTING_AMOUNT);
        timeElapsed = uint64(bound(timeElapsed, vestingCliff, vestingDuration));

        _deployProxy(uint256(block.timestamp), vestingDuration, vestingCliff);
        deal(address(seam), address(proxy), vestingAmount);

        // Move past cliff
        vm.warp(block.timestamp + timeElapsed);

        // Calculate expected vested amount
        uint256 expectedVested = (vestingAmount * timeElapsed) / vestingDuration;
        assertEq(proxy.vestedAmount(uint64(block.timestamp)), expectedVested);

        // Release tokens
        uint256 balanceBefore = seam.balanceOf(beneficiary);
        vm.prank(beneficiary);
        proxy.release();
        assertEq(seam.balanceOf(beneficiary) - balanceBefore, expectedVested);
        assertEq(proxy.releasable(), 0);
    }

    function testFuzz_Fork_StakeWithVotingPower(uint64 vestingDuration, uint256 vestingAmount, uint256 stakePercent)
        public
    {
        vestingDuration = uint64(bound(vestingDuration, MIN_DURATION, MAX_DURATION));
        vestingAmount = bound(vestingAmount, MIN_VESTING_AMOUNT, MAX_VESTING_AMOUNT);
        stakePercent = bound(stakePercent, 1, 100);

        _deployProxy(uint256(block.timestamp), vestingDuration, 0); // No cliff for simplicity
        deal(address(seam), address(proxy), vestingAmount);

        vm.warp(block.timestamp + vestingDuration / 2);

        // Calculate stake amount as percentage of vested tokens
        uint256 vestedAmount = proxy.vestedAmount(uint64(block.timestamp));
        uint256 stakeAmount = (vestedAmount * stakePercent) / 100;

        // Setup for staking
        vm.startPrank(beneficiary);

        // Stake tokens
        proxy.stake(stakeAmount);

        // Delegate to self to activate voting power
        proxy.delegate(address(stkSeam), address(beneficiary));

        vm.stopPrank();

        // Verify increased voting power
        assertEq(stkSeam.getVotes(address(beneficiary)), stakeAmount);
        assertEq(stkSeam.balanceOf(address(proxy)), stakeAmount);
    }

    function testFuzz_Fork_ClaimRewards(
        uint64 vestingDuration,
        uint256 vestingAmount,
        uint256 stakePercent,
        uint256 timeAfterStaking
    ) public {
        vestingDuration = uint64(bound(vestingDuration, MIN_DURATION, MAX_DURATION));
        vestingAmount = bound(vestingAmount, MIN_VESTING_AMOUNT, MAX_VESTING_AMOUNT);
        stakePercent = bound(stakePercent, 1, 100);
        timeAfterStaking = bound(timeAfterStaking, 1 days, 30 days);

        _deployProxy(uint256(block.timestamp), vestingDuration, 0); // No cliff for simplicity
        deal(address(seam), address(proxy), vestingAmount);

        // Warp to middle of vesting period
        vm.warp(block.timestamp + vestingDuration / 2);

        // Calculate stake amount as percentage of vested tokens
        uint256 vestedAmount = proxy.vestedAmount(uint64(block.timestamp));
        uint256 stakeAmount = (vestedAmount * stakePercent) / 100;

        // Setup rewards
        FeeKeeper feeKeeper = FeeKeeper(Constants.FEE_KEEPER);

        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(seam, address(feeKeeper.getController()), address(feeKeeper));

        deal(address(seam), address(transferStrategy), 1e18 * timeAfterStaking);

        vm.startPrank(Constants.SHORT_TIMELOCK_ADDRESS);

        feeKeeper.setTokenForManualRate(address(seam), true);
        feeKeeper.configureAsset(
            address(seam),
            1e18,
            uint32(block.timestamp + timeAfterStaking),
            address(transferStrategy),
            Constants.ORACLE_PLACEHOLDER
        );

        vm.stopPrank();

        // Stake tokens
        vm.prank(beneficiary);
        proxy.stake(stakeAmount);

        // Warp forward to accumulate rewards
        vm.warp(block.timestamp + timeAfterStaking);

        // Claim rewards
        address[] memory assets = new address[](1);
        assets[0] = address(stkSeam);

        uint256 balanceBefore = seam.balanceOf(beneficiary);

        vm.prank(beneficiary);
        proxy.claimRewards(assets, 1, beneficiary, address(seam));

        assertEq(seam.balanceOf(beneficiary) - balanceBefore, 1);
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
