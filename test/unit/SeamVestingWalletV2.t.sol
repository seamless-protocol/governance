// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SeamVestingWalletV2} from "../../src/SeamVestingWalletV2.sol";
import {ISeamVestingWalletV2} from "../../src/interfaces/ISeamVestingWalletV2.sol";
import {ERC1967Proxy, ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC4626Mock} from "openzeppelin-contracts/mocks/token/ERC4626Mock.sol";
import {StakedToken, IVotes} from "../../src/StakedToken.sol";
import {IStakedToken} from "../../src/interfaces/IStakedToken.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract SeamVestingWalletV2Test is Test {
    SeamVestingWalletV2 seamVestingWallet;

    ERC4626Mock stakedTokenMock;
    ERC20Mock token;

    address rewardsController = makeAddr("rewardsController");
    address beneficiary = makeAddr("beneficiary");
    address owner = makeAddr("owner");

    uint64 constant DEFAULT_VESTING_DURATION = 300;
    uint64 constant DEFAULT_VESTING_CLIFF = 100;

    function setUp() public {
        token = new ERC20Mock();
        stakedTokenMock = new ERC4626Mock(address(token));

        // Mock StakedToken.getRewardsController
        vm.mockCall(
            address(stakedTokenMock),
            abi.encodeWithSelector(IStakedToken.getRewardsController.selector),
            abi.encode(rewardsController)
        );

        SeamVestingWalletV2 implementation = new SeamVestingWalletV2();
        ERC1967Proxy proxy_ = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                SeamVestingWalletV2.initialize.selector,
                owner,
                beneficiary,
                IERC20(address(token)),
                StakedToken(address(stakedTokenMock)),
                uint64(block.timestamp),
                DEFAULT_VESTING_DURATION,
                DEFAULT_VESTING_CLIFF
            )
        );
        seamVestingWallet = SeamVestingWalletV2(address(proxy_));
    }

    function test_Deployed() public view {
        assertEq(seamVestingWallet.vestingStart(), 1);
        assertEq(seamVestingWallet.vestingDuration(), DEFAULT_VESTING_DURATION);
        assertEq(seamVestingWallet.vestingCliff(), DEFAULT_VESTING_CLIFF);
        assertEq(seamVestingWallet.vestingEnd(), 1 + DEFAULT_VESTING_DURATION);
        assertEq(seamVestingWallet.released(), 0);
        assertEq(seamVestingWallet.releasable(), 0);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(seamVestingWallet.owner(), owner);
        assertEq(seamVestingWallet.beneficiary(), beneficiary);
        assertEq(seamVestingWallet.lockupEnd(), 0);
    }

    function testFuzz_Deployed(uint64 vestingDuration, uint64 vestingCliff) public {
        vestingDuration = uint64(bound(vestingDuration, 1, type(uint64).max - 1));
        vestingCliff = uint64(bound(vestingCliff, 0, vestingDuration));

        SeamVestingWalletV2 implementation = new SeamVestingWalletV2();
        SeamVestingWalletV2 proxy = SeamVestingWalletV2(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeWithSelector(
                        SeamVestingWalletV2.initialize.selector,
                        owner,
                        beneficiary,
                        IERC20(address(token)),
                        StakedToken(address(stakedTokenMock)),
                        uint64(block.timestamp),
                        vestingDuration,
                        vestingCliff
                    )
                )
            )
        );

        assertEq(proxy.vestingStart(), uint64(block.timestamp));
        assertEq(proxy.vestingDuration(), vestingDuration);
        assertEq(proxy.vestingCliff(), vestingCliff);
        assertEq(proxy.vestingEnd(), uint64(block.timestamp) + vestingDuration);
        assertEq(proxy.released(), 0);
        assertEq(proxy.releasable(), 0);
        assertEq(proxy.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(proxy.owner(), owner);
        assertEq(proxy.beneficiary(), beneficiary);
        assertEq(proxy.lockupEnd(), 0);
    }

    function test_Upgrade() public {
        address newImplementation = address(new SeamVestingWalletV2());

        vm.startPrank(owner);

        vm.expectEmit(true, true, false, false);
        emit ERC1967Utils.Upgraded(newImplementation);
        seamVestingWallet.upgradeToAndCall(address(newImplementation), "");

        vm.stopPrank();
    }

    function test_Upgrade_RevertIf_NotOwner() public {
        address newImplementation = address(new SeamVestingWalletV2());

        vm.startPrank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, beneficiary));
        seamVestingWallet.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    function testFuzz_SetVestingStart(uint64 startTimestamp) public {
        vm.startPrank(owner);

        seamVestingWallet.setVestingStart(startTimestamp);
        assertEq(seamVestingWallet.vestingStart(), startTimestamp);

        vm.stopPrank();
    }

    function test_SetVestingStart_RevertIf_NotOwner() public {
        vm.startPrank(beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, beneficiary));
        seamVestingWallet.setVestingStart(1);

        vm.stopPrank();
    }

    function testFuzz_SetVestingDuration(uint64 newDuration) public {
        newDuration = uint64(bound(newDuration, DEFAULT_VESTING_CLIFF + 1, type(uint64).max));

        vm.startPrank(owner);

        vm.expectEmit();
        emit ISeamVestingWalletV2.VestingDurationSet(newDuration);
        seamVestingWallet.setVestingDuration(newDuration);
        assertEq(seamVestingWallet.vestingDuration(), newDuration);

        vm.stopPrank();
    }

    function test_SetVestingDuration_RevertIf_NotOwner() public {
        vm.startPrank(beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, beneficiary));
        seamVestingWallet.setVestingDuration(200);

        vm.stopPrank();
    }

    function testFuzz_SetVestingDuration_RevertIf_InvalidDuration(uint64 newDuration) public {
        newDuration = uint64(bound(newDuration, 0, DEFAULT_VESTING_CLIFF - 1));

        vm.startPrank(owner);

        // Can't set duration less than cliff
        vm.expectRevert(ISeamVestingWalletV2.InvalidDuration.selector);
        seamVestingWallet.setVestingDuration(newDuration);

        vm.stopPrank();
    }

    function testFuzz_SetVestingCliff(uint64 newCliff) public {
        newCliff = uint64(bound(newCliff, 0, DEFAULT_VESTING_DURATION));

        vm.startPrank(owner);

        vm.expectEmit();
        emit ISeamVestingWalletV2.VestingCliffSet(newCliff);
        seamVestingWallet.setVestingCliff(newCliff);

        assertEq(seamVestingWallet.vestingCliff(), newCliff);

        vm.stopPrank();
    }

    function test_SetVestingCliff_RevertIf_NotOwner() public {
        vm.startPrank(beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, beneficiary));
        seamVestingWallet.setVestingCliff(50);

        vm.stopPrank();
    }

    function testFuzz_SetVestingCliff_RevertIf_InvalidCliff(uint64 newCliff) public {
        newCliff = uint64(bound(newCliff, DEFAULT_VESTING_DURATION + 1, type(uint64).max));

        vm.startPrank(owner);

        // Can't set cliff greater than duration
        vm.expectRevert(ISeamVestingWalletV2.InvalidCliff.selector);
        seamVestingWallet.setVestingCliff(newCliff);

        vm.stopPrank();
    }

    function testFuzz_SetLockupEnd(uint64 end) public {
        end = uint64(bound(end, 0, type(uint64).max - 1));

        vm.startPrank(owner);

        vm.expectEmit();
        emit ISeamVestingWalletV2.LockupEndSet(end);
        seamVestingWallet.setLockupEnd(end);
        assertEq(seamVestingWallet.lockupEnd(), end);

        vm.stopPrank();
    }

    function test_SetLockupEnd_RevertIf_NotOwner() public {
        vm.startPrank(beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, beneficiary));
        seamVestingWallet.setLockupEnd(1000);

        vm.stopPrank();
    }

    function testFuzz_Transfer(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 0, type(uint256).max);
        deal(address(token), address(seamVestingWallet), withdrawAmount);

        uint256 balanceThisBefore = token.balanceOf(address(this));
        uint256 balanceVestingWalletBefore = token.balanceOf(address(seamVestingWallet));

        vm.prank(owner);
        seamVestingWallet.transfer(address(token), address(this), withdrawAmount);

        assertEq(token.balanceOf(address(this)), balanceThisBefore + withdrawAmount);
        assertEq(token.balanceOf(address(seamVestingWallet)), balanceVestingWalletBefore - withdrawAmount);
    }

    function test_Transfer_RevertIf_NotOwner() public {
        vm.startPrank(beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, beneficiary));
        seamVestingWallet.transfer(address(token), address(this), 1);

        vm.stopPrank();
    }

    function test_Delegate() public {
        vm.startPrank(beneficiary);

        address delegatee1 = makeAddr("delegatee1");
        address delegatee2 = makeAddr("delegatee2");

        // Mock delegation calls
        vm.mockCall(address(token), abi.encodeWithSelector(IVotes.delegate.selector, delegatee1), abi.encode());

        vm.mockCall(
            address(stakedTokenMock), abi.encodeWithSelector(IVotes.delegate.selector, delegatee2), abi.encode()
        );

        // Test both token and stakedToken delegation
        vm.expectCall(address(token), abi.encodeWithSelector(IVotes.delegate.selector, delegatee1));
        seamVestingWallet.delegate(address(token), delegatee1);

        vm.expectCall(address(stakedTokenMock), abi.encodeWithSelector(IVotes.delegate.selector, delegatee2));
        seamVestingWallet.delegate(address(stakedTokenMock), delegatee2);

        vm.stopPrank();
    }

    function test_Delegate_RevertIf_NotBeneficiary() public {
        address notBeneficiary = makeAddr("notBeneficiary");

        vm.startPrank(notBeneficiary);

        vm.expectRevert(abi.encodeWithSelector(ISeamVestingWalletV2.NotBeneficiary.selector, notBeneficiary));
        seamVestingWallet.delegate(address(token), makeAddr("delegatee"));

        vm.stopPrank();
    }

    function test_Delegate_RevertIf_InvalidToken() public {
        address invalidToken = makeAddr("invalidToken");

        vm.startPrank(beneficiary);

        vm.expectRevert(ISeamVestingWalletV2.InvalidToken.selector);
        seamVestingWallet.delegate(invalidToken, makeAddr("delegatee"));

        vm.stopPrank();
    }

    function testFuzz_VestBeforeStart(uint64 futureStart) public {
        futureStart = uint64(bound(futureStart, block.timestamp, type(uint64).max - DEFAULT_VESTING_CLIFF));

        deal(address(token), address(seamVestingWallet), 1000 ether);

        vm.prank(owner);
        seamVestingWallet.setVestingStart(futureStart);

        assertEq(seamVestingWallet.releasable(), 0);
    }

    function testFuzz_VestBeforeCliff(uint64 timestamp) public {
        timestamp = uint64(bound(timestamp, block.timestamp, block.timestamp + DEFAULT_VESTING_CLIFF - 1));

        deal(address(token), address(seamVestingWallet), 1000 ether);

        vm.warp(timestamp);

        assertEq(seamVestingWallet.releasable(), 0);
    }

    function testFuzz_VestAfterEnd(uint64 timestamp, uint256 totalAllocation) public {
        timestamp = uint64(bound(timestamp, block.timestamp + DEFAULT_VESTING_DURATION + 1, type(uint64).max));
        totalAllocation = bound(totalAllocation, 1, type(uint256).max);

        deal(address(token), address(seamVestingWallet), totalAllocation);

        vm.warp(timestamp);

        assertEq(seamVestingWallet.releasable(), totalAllocation);
    }

    function testFuzz_VestDuringLockup(uint64 timestamp) public {
        timestamp = uint64(
            bound(timestamp, block.timestamp + DEFAULT_VESTING_CLIFF, block.timestamp + DEFAULT_VESTING_DURATION)
        );

        deal(address(token), address(seamVestingWallet), 1000 ether);

        // Set lockup period to current time with fuzzed duration
        vm.startPrank(owner);
        seamVestingWallet.setLockupEnd(uint64(seamVestingWallet.vestingEnd()));
        vm.stopPrank();

        vm.warp(timestamp);

        // During lockup, nothing should be releasable
        assertEq(seamVestingWallet.releasable(), 0);
        assertGt(seamVestingWallet.vestedAmount(timestamp), 0);
    }

    function testFuzz_Vest(uint256 totalAllocation, uint64 percentVested) public {
        percentVested = uint64(bound(percentVested, 0, 100));

        deal(address(token), address(seamVestingWallet), totalAllocation);

        // Ensure we're past the cliff period
        uint64 timeElapsed = (DEFAULT_VESTING_DURATION * percentVested) / 100;
        vm.warp(uint64(block.timestamp) + timeElapsed);

        uint256 expectedVestedAmount =
            timeElapsed < DEFAULT_VESTING_CLIFF ? 0 : Math.mulDiv(totalAllocation, percentVested, 100);

        assertEq(seamVestingWallet.releasable(), expectedVestedAmount);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
        assertEq(seamVestingWallet.released(), 0);

        uint256 balanceBeneficiaryBefore = token.balanceOf(beneficiary);
        uint256 balanceVestingWalletBefore = token.balanceOf(address(seamVestingWallet));

        seamVestingWallet.release();

        assertEq(token.balanceOf(beneficiary), balanceBeneficiaryBefore + expectedVestedAmount);
        assertEq(token.balanceOf(address(seamVestingWallet)), balanceVestingWalletBefore - expectedVestedAmount);
        assertEq(seamVestingWallet.released(), expectedVestedAmount);
        assertEq(seamVestingWallet.releasable(), 0);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
    }

    function testFuzz_VestAddedBalance(uint256 startingAllocation, uint256 addedAmount, uint64 percentVested) public {
        percentVested = uint64(bound(percentVested, 0, 100));
        startingAllocation = bound(startingAllocation, 0, type(uint256).max - addedAmount);

        // Ensure we're past the cliff period
        uint64 timeElapsed = (DEFAULT_VESTING_DURATION * percentVested) / 100;
        vm.warp(uint64(block.timestamp) + timeElapsed);

        deal(address(token), address(seamVestingWallet), startingAllocation);

        uint256 expectedVestedAmount =
            timeElapsed < DEFAULT_VESTING_CLIFF ? 0 : Math.mulDiv(startingAllocation, percentVested, 100);

        assertEq(seamVestingWallet.releasable(), expectedVestedAmount);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
        assertEq(seamVestingWallet.released(), 0);

        uint256 expectedVestedAmountAfterTransfer =
            timeElapsed < DEFAULT_VESTING_CLIFF ? 0 : Math.mulDiv(startingAllocation + addedAmount, percentVested, 100);

        uint256 snapshot = vm.snapshotState();

        seamVestingWallet.release();

        token.mint(address(seamVestingWallet), addedAmount);

        assertEq(seamVestingWallet.releasable(), expectedVestedAmountAfterTransfer - expectedVestedAmount);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), expectedVestedAmountAfterTransfer);
        assertEq(seamVestingWallet.released(), expectedVestedAmount);

        vm.revertToState(snapshot);

        token.mint(address(seamVestingWallet), addedAmount);

        assertEq(seamVestingWallet.releasable(), expectedVestedAmountAfterTransfer);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), expectedVestedAmountAfterTransfer);
        assertEq(seamVestingWallet.released(), 0);
    }

    function testFuzz_VestRemovedBalance(uint256 startingAllocation, uint256 removedAmount, uint64 percentVested)
        public
    {
        percentVested = uint64(bound(percentVested, 0, 100));

        // Ensure we're past the cliff period
        uint64 timeElapsed = (DEFAULT_VESTING_DURATION * percentVested) / 100;
        vm.warp(uint64(block.timestamp) + timeElapsed);

        uint256 expectedVestedAmount =
            timeElapsed < DEFAULT_VESTING_CLIFF ? 0 : Math.mulDiv(startingAllocation, percentVested, 100);

        removedAmount = bound(removedAmount, 0, startingAllocation - expectedVestedAmount);

        deal(address(token), address(seamVestingWallet), startingAllocation);

        assertEq(seamVestingWallet.releasable(), expectedVestedAmount);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
        assertEq(seamVestingWallet.released(), 0);

        // Transfer tokens out of the vesting wallet
        vm.prank(owner);
        seamVestingWallet.transfer(address(token), address(this), removedAmount);

        uint256 expectedVestedAmountAfterRemoval = timeElapsed < DEFAULT_VESTING_CLIFF
            ? 0
            : Math.mulDiv(startingAllocation - removedAmount, percentVested, 100);

        assertEq(seamVestingWallet.releasable(), expectedVestedAmountAfterRemoval);
        assertEq(seamVestingWallet.vestedAmount(uint64(block.timestamp)), expectedVestedAmountAfterRemoval);
        assertEq(seamVestingWallet.released(), 0);
    }

    function testFuzz_Stake(uint64 timestamp, uint256 totalAllocation, uint256 stakeAmount) public {
        deal(address(token), address(seamVestingWallet), totalAllocation);

        timestamp = uint64(bound(timestamp, block.timestamp + DEFAULT_VESTING_CLIFF, type(uint64).max));
        stakeAmount = bound(stakeAmount, 0, seamVestingWallet.vestedAmount(timestamp));

        vm.warp(timestamp);

        uint256 releaseableBefore = seamVestingWallet.releasable();

        vm.prank(beneficiary);
        seamVestingWallet.stake(stakeAmount);

        assertEq(seamVestingWallet.stakedAmount(), stakeAmount);
        assertEq(stakedTokenMock.balanceOf(address(seamVestingWallet)), stakeAmount);
        assertEq(seamVestingWallet.releasable(), releaseableBefore - stakeAmount);
    }

    function testFuzz_Stake_Max(uint64 timestamp, uint256 totalAllocation) public {
        totalAllocation = bound(totalAllocation, 1, type(uint256).max);
        timestamp = uint64(bound(timestamp, block.timestamp + DEFAULT_VESTING_CLIFF, type(uint64).max));

        deal(address(token), address(seamVestingWallet), totalAllocation);

        vm.warp(timestamp);

        uint256 vestedAmount = seamVestingWallet.vestedAmount(timestamp);

        vm.prank(beneficiary);
        seamVestingWallet.stake(type(uint256).max);

        assertEq(seamVestingWallet.stakedAmount(), vestedAmount);
        assertEq(stakedTokenMock.balanceOf(address(seamVestingWallet)), vestedAmount);
        assertEq(seamVestingWallet.releasable(), 0);
    }

    function test_Stake_RevertIf_NotBeneficiary() public {
        address notBeneficiary = makeAddr("notBeneficiary");

        vm.startPrank(notBeneficiary);

        vm.expectRevert(abi.encodeWithSelector(ISeamVestingWalletV2.NotBeneficiary.selector, notBeneficiary));
        seamVestingWallet.stake(100);

        vm.stopPrank();
    }

    function testFuzz_Stake_RevertIf_InsufficientVestedTokens(
        uint64 timestamp,
        uint256 totalAllocation,
        uint256 stakeAmount
    ) public {
        totalAllocation = bound(totalAllocation, 1, type(uint256).max - 2);
        timestamp = uint64(bound(timestamp, block.timestamp + DEFAULT_VESTING_CLIFF, type(uint64).max));

        deal(address(token), address(seamVestingWallet), totalAllocation);

        vm.warp(timestamp);

        uint256 vestedAmount = seamVestingWallet.vestedAmount(timestamp);
        stakeAmount = bound(stakeAmount, vestedAmount + 1, type(uint256).max - 1);

        vm.startPrank(beneficiary);

        vm.expectRevert(
            abi.encodeWithSelector(ISeamVestingWalletV2.InsufficientVestedTokens.selector, stakeAmount, vestedAmount)
        );
        seamVestingWallet.stake(stakeAmount);

        vm.stopPrank();
    }

    function testFuzz_Stake_MultipleTimesAsMoreTokensVest(uint64 timestamp1, uint64 timestamp2, uint256 totalAllocation)
        public
    {
        // Ensure timestamps are within valid range and timestamp2 > timestamp1
        timestamp1 = uint64(bound(timestamp1, block.timestamp + DEFAULT_VESTING_CLIFF, DEFAULT_VESTING_DURATION - 1));
        timestamp2 = uint64(bound(timestamp2, timestamp1 + 1, DEFAULT_VESTING_DURATION));
        totalAllocation = bound(totalAllocation, 2, type(uint256).max);

        deal(address(token), address(seamVestingWallet), totalAllocation);

        // First staking at timestamp1
        vm.warp(timestamp1);
        uint256 vestedAmount = seamVestingWallet.vestedAmount(timestamp1);

        vm.startPrank(beneficiary);
        seamVestingWallet.stake(type(uint256).max);

        assertEq(seamVestingWallet.stakedAmount(), vestedAmount);
        assertEq(stakedTokenMock.balanceOf(address(seamVestingWallet)), vestedAmount);
        assertEq(seamVestingWallet.releasable(), 0);

        // Second staking at timestamp2 when more tokens have vested
        vm.warp(timestamp2);
        vestedAmount = seamVestingWallet.vestedAmount(timestamp2);

        // Stake the additional vested amount
        seamVestingWallet.stake(type(uint256).max);

        // Verify total staked amount equals total vested amount at timestamp2
        assertEq(seamVestingWallet.stakedAmount(), vestedAmount);
        assertEq(stakedTokenMock.balanceOf(address(seamVestingWallet)), vestedAmount);
        assertEq(seamVestingWallet.releasable(), 0);

        vm.stopPrank();
    }

    function test_Cooldown() public {
        vm.startPrank(beneficiary);

        vm.mockCall(address(stakedTokenMock), abi.encodeWithSelector(IStakedToken.cooldown.selector), abi.encode());

        vm.expectCall(address(stakedTokenMock), abi.encodeWithSelector(IStakedToken.cooldown.selector));
        seamVestingWallet.cooldown();

        vm.stopPrank();
    }

    function test_Cooldown_RevertIf_NotBeneficiary() public {
        address notBeneficiary = makeAddr("notBeneficiary");

        vm.startPrank(notBeneficiary);

        vm.expectRevert(abi.encodeWithSelector(ISeamVestingWalletV2.NotBeneficiary.selector, notBeneficiary));
        seamVestingWallet.cooldown();

        vm.stopPrank();
    }

    function testFuzz_Unstake(uint64 timestamp, uint256 totalAllocation, uint256 unstakeAmount) public {
        totalAllocation = bound(totalAllocation, 1, type(uint256).max - 1);

        deal(address(token), address(seamVestingWallet), totalAllocation);

        timestamp = uint64(bound(timestamp, block.timestamp + DEFAULT_VESTING_CLIFF, type(uint64).max));

        vm.warp(timestamp);

        vm.startPrank(beneficiary);

        uint256 stakeAmount = seamVestingWallet.vestedAmount(timestamp);

        unstakeAmount = bound(unstakeAmount, 0, stakeAmount);

        seamVestingWallet.stake(stakeAmount);

        uint256 stakedAmountBefore = seamVestingWallet.stakedAmount();

        // Now unstake
        seamVestingWallet.unstake(unstakeAmount);

        // Verify the unstake was successful
        assertEq(stakedTokenMock.balanceOf(address(seamVestingWallet)), stakedAmountBefore - unstakeAmount);
        assertEq(seamVestingWallet.stakedAmount(), stakedAmountBefore - unstakeAmount);
        assertEq(seamVestingWallet.releasable(), unstakeAmount);

        vm.stopPrank();
    }

    function testFuzz_Unstake_WhenRedeemReturnsMoreAssets(uint64 timestamp, uint256 totalAllocation) public {
        totalAllocation = bound(totalAllocation, 1, type(uint256).max - 101e18);

        deal(address(token), address(seamVestingWallet), totalAllocation);

        timestamp = uint64(bound(timestamp, block.timestamp + DEFAULT_VESTING_CLIFF, type(uint64).max));

        vm.warp(timestamp);

        vm.startPrank(beneficiary);

        seamVestingWallet.stake(type(uint256).max);

        uint256 stakedAmountBefore = seamVestingWallet.stakedAmount();

        vm.stopPrank();

        // Donate 1e18 token to the stakedToken contract
        address tempAddress = makeAddr("tempAddress");
        deal(address(token), address(tempAddress), 100e18);

        vm.prank(tempAddress);
        token.transfer(address(stakedTokenMock), 100e18);

        vm.startPrank(beneficiary);

        // Now unstake
        seamVestingWallet.unstake(stakedAmountBefore);

        // Verify the unstake was successful
        assertEq(stakedTokenMock.balanceOf(address(seamVestingWallet)), 0);
        assertEq(seamVestingWallet.stakedAmount(), 0);

        vm.stopPrank();
    }

    function test_Unstake_RevertIf_NotBeneficiary() public {
        address notBeneficiary = makeAddr("notBeneficiary");

        vm.startPrank(notBeneficiary);

        vm.expectRevert(abi.encodeWithSelector(ISeamVestingWalletV2.NotBeneficiary.selector, notBeneficiary));
        seamVestingWallet.unstake(100);

        vm.stopPrank();
    }

    function test_ClaimRewards() public {
        address[] memory assets = new address[](1);
        assets[0] = address(stakedTokenMock);
        uint256 rewardAmount = 100;
        address rewardToken = makeAddr("rewardToken");

        vm.startPrank(beneficiary);

        vm.mockCall(
            address(rewardsController),
            abi.encodeWithSelector(
                IRewardsController.claimRewards.selector, assets, rewardAmount, beneficiary, rewardToken
            ),
            abi.encode(0)
        );

        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                IRewardsController.claimRewards.selector, assets, rewardAmount, beneficiary, rewardToken
            )
        );
        seamVestingWallet.claimRewards(assets, rewardAmount, beneficiary, rewardToken);

        vm.stopPrank();
    }

    function test_ClaimAllStakedRewards() public {
        address[] memory assets = new address[](1);
        assets[0] = address(stakedTokenMock);

        vm.startPrank(beneficiary);

        address[] memory rewards = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        // Mock the claimAllRewards call
        vm.mockCall(
            address(rewardsController),
            abi.encodeWithSelector(IRewardsController.claimAllRewards.selector, assets, beneficiary),
            abi.encode(rewards, amounts)
        );

        // Expect the call to be made with correct parameters
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(IRewardsController.claimAllRewards.selector, assets, beneficiary)
        );

        // Call the function
        seamVestingWallet.claimAllStakedRewards(beneficiary);

        vm.stopPrank();
    }

    function test_ClaimRewards_RevertIf_NotBeneficiary() public {
        address[] memory assets = new address[](1);
        assets[0] = address(stakedTokenMock);

        address notBeneficiary = makeAddr("notBeneficiary");

        vm.startPrank(notBeneficiary);

        vm.expectRevert(abi.encodeWithSelector(ISeamVestingWalletV2.NotBeneficiary.selector, notBeneficiary));
        seamVestingWallet.claimRewards(assets, 100, beneficiary, address(token));

        vm.expectRevert(abi.encodeWithSelector(ISeamVestingWalletV2.NotBeneficiary.selector, notBeneficiary));
        seamVestingWallet.claimAllStakedRewards(beneficiary);

        vm.stopPrank();
    }

    function test_SetBeneficiary() public {
        address newBeneficiary = makeAddr("newBeneficiary");

        vm.startPrank(owner);

        vm.expectEmit(true, true, false, false);
        emit ISeamVestingWalletV2.BeneficiaryChanged(beneficiary, newBeneficiary);
        seamVestingWallet.setBeneficiary(newBeneficiary);

        assertEq(seamVestingWallet.beneficiary(), newBeneficiary);

        vm.stopPrank();
    }

    function test_SetBeneficiary_RevertIf_NotOwner() public {
        vm.startPrank(beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, beneficiary));
        seamVestingWallet.setBeneficiary(makeAddr("newBeneficiary"));

        vm.stopPrank();
    }
}
