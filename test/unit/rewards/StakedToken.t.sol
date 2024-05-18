// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Staking} from "src/rewards/Staking.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {User} from "../../scenarios/rewards/User.sol";
import {RewardTokenData} from "../../../src/types/DataTypes.sol";
import {EscrowSeam} from "../../../src/EscrowSeam.sol";

contract StakingTest is Test {
    uint256 public constant ABS_TOLERANCE = 3 wei;
    uint256 public constant EMISSION_PER_SECOND = 10000 wei;

    ERC20Mock public seam = new ERC20Mock();
    ERC20Mock public token = new ERC20Mock();
    ERC20Mock public rewardToken = new ERC20Mock();

    ERC20Mock public esSeam;
    Staking public staking;

    User public user;

    function setUp() public {
        EscrowSeam escrowSeamImplementation = new EscrowSeam();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(escrowSeamImplementation),
            abi.encodeWithSelector(EscrowSeam.initialize.selector, address(seam), 365 days, address(this))
        );
        esSeam = ERC20Mock(address(proxy));

        Staking stakingImplementation = new Staking();
        proxy = new ERC1967Proxy(
            address(stakingImplementation),
            abi.encodeWithSelector(Staking.initialize.selector, address(seam), address(esSeam), address(this))
        );

        staking = Staking(address(proxy));
        user = new User(token, seam, staking);

        staking.startStaking(address(token));
        staking.startStaking(address(seam));
        staking.configureRewardToken(address(token), address(rewardToken), EMISSION_PER_SECOND);
        staking.configureRewardToken(address(seam), address(esSeam), EMISSION_PER_SECOND);
        rewardToken.mint(address(staking), type(uint256).max);
        seam.mint(address(staking), type(uint256).max / 2);
    }

    function testFuzz_StartStaking(address newToken) public {
        vm.assume(newToken != address(token) && newToken != address(seam));
        staking.startStaking(newToken);

        assertEq(staking.getStakingTokens().length, 3);
        assertEq(staking.getStakingTokens()[2], newToken);
        assertEq(staking.getEmissionPerSecond(newToken, address(rewardToken)), 0);
        assertEq(staking.getRewardTokens(newToken).length, 0);
        assertNotEq(staking.getStakedToken(newToken), address(0));
    }

    function testFuzz_StartStaking_RevertStakingTokenAlreadyAdded(address newToken) public {
        vm.assume(newToken != address(token) && newToken != address(seam));
        staking.startStaking(newToken);

        vm.expectRevert(IStaking.StakingAlreadyStarted.selector);
        staking.startStaking(newToken);
    }

    function testFuzz_ConfigureRewardToken(address asset, uint256 emissionPerSecond1, uint256 emissionPerSecond2)
        public
    {
        staking.configureRewardToken(address(token), asset, emissionPerSecond1);
        assertEq(staking.getEmissionPerSecond(address(token), asset), emissionPerSecond1);

        RewardTokenData memory rewardTokenData = staking.getRewardTokenData(address(token), asset);
        assertEq(rewardTokenData.rewardPerStakedToken, 0);
        assertEq(rewardTokenData.lastUpdatedTimestamp, block.timestamp);

        staking.configureRewardToken(address(token), asset, emissionPerSecond2);
        assertEq(staking.getEmissionPerSecond(address(token), asset), emissionPerSecond2);

        rewardTokenData = staking.getRewardTokenData(address(token), asset);
        assertEq(rewardTokenData.rewardPerStakedToken, 0);
        assertEq(rewardTokenData.lastUpdatedTimestamp, block.timestamp);
    }

    function testFuzz_ConfigureRewardToken_RevertAsetNotWhitelisted(
        address stakingAsset,
        address rewardAsset,
        uint256 emissionPerSecond
    ) public {
        vm.assume(stakingAsset != address(token));
        vm.expectRevert(IStaking.StakingNotStarted.selector);
        staking.configureRewardToken(stakingAsset, rewardAsset, emissionPerSecond);
    }

    function testFuzz_Deposit(uint256 amount1, uint256 amount2, uint256 timePassed) public {
        amount1 = bound(amount1, 1, 1_000_000_000 ether);
        amount2 = bound(amount2, 1, 1_000_000_000 ether);
        timePassed = bound(timePassed, 1, 365 days);

        token.mint(address(user), amount1);
        user.deposit(amount1);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(staking)), amount1);
        assertEq(staking.getUserStakedBalance(address(user), address(token)), amount1);
        assertEq(staking.getTotalStaked(address(token)), amount1);
        assertEq(staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)), 0);
        assertEq(staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)), 0);

        RewardTokenData memory rewardTokenData = staking.getRewardTokenData(address(token), address(rewardToken));

        assertEq(rewardTokenData.rewardPerStakedToken, 0);
        assertEq(rewardTokenData.lastUpdatedTimestamp, block.timestamp);

        vm.warp(block.timestamp + timePassed);

        token.mint(address(user), amount2);
        user.deposit(amount2);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(staking)), amount1 + amount2);
        assertEq(staking.getUserStakedBalance(address(user), address(token)), amount1 + amount2);
        assertEq(staking.getTotalStaked(address(token)), amount1 + amount2);

        uint256 totalAccruedRewards = EMISSION_PER_SECOND * timePassed;
        assertApproxEqAbs(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)),
            totalAccruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)),
            totalAccruedRewards
        );

        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            totalAccruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            totalAccruedRewards
        );
    }

    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount, uint256 timePassed) public {
        depositAmount = bound(depositAmount, 1, 1_000_000_000 ether);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        timePassed = bound(timePassed, 1, 365 days);

        token.mint(address(user), depositAmount);
        user.deposit(depositAmount);

        vm.warp(block.timestamp + timePassed);

        user.withdraw(withdrawAmount);

        assertEq(token.balanceOf(address(user)), withdrawAmount);
        assertEq(token.balanceOf(address(staking)), depositAmount - withdrawAmount);
        assertEq(staking.getUserStakedBalance(address(user), address(token)), depositAmount - withdrawAmount);
        assertEq(staking.getTotalStaked(address(token)), depositAmount - withdrawAmount);

        uint256 accruedRewards = EMISSION_PER_SECOND * timePassed;
        assertApproxEqAbs(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)), accruedRewards
        );

        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)), accruedRewards
        );
    }

    function testFuzz_WithdrawSeam(uint256 depositAmount, uint256 withdrawAmount, uint256 timePassed) public {
        depositAmount = bound(depositAmount, 1, 1_000_000_000 ether);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        timePassed = bound(timePassed, 1, 365 days);

        uint256 seamContractBalanceBefore = seam.balanceOf(address(staking));
        seam.mint(address(user), depositAmount);
        user.depositSeam(depositAmount);

        vm.warp(block.timestamp + timePassed);

        user.withdrawSeam(withdrawAmount);

        assertEq(esSeam.balanceOf(address(user)), withdrawAmount);
        assertEq(seam.balanceOf(address(staking)), seamContractBalanceBefore + depositAmount - withdrawAmount);
        assertEq(staking.getUserStakedBalance(address(user), address(seam)), depositAmount - withdrawAmount);
        assertEq(staking.getTotalStaked(address(seam)), depositAmount - withdrawAmount);
    }

    function testFuzz_ClaimRewards(uint256 depositAmount, uint256 timePassed) public {
        depositAmount = bound(depositAmount, 1, 1_000_000_000 ether);
        timePassed = bound(timePassed, 1, 365 days);

        token.mint(address(user), depositAmount);
        user.deposit(depositAmount);

        vm.warp(block.timestamp + timePassed);

        uint256 rewardAmountOnContractBeforeClaim = rewardToken.balanceOf(address(staking));
        user.claimRewards();

        uint256 accruedRewards = EMISSION_PER_SECOND * timePassed;
        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(staking)), depositAmount);
        assertEq(staking.getUserStakedBalance(address(user), address(token)), depositAmount);
        assertEq(staking.getTotalStaked(address(token)), depositAmount);

        assertEq(staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)), 0);
        assertEq(staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(user)), accruedRewards, ABS_TOLERANCE);
        assertLe(rewardToken.balanceOf(address(user)), accruedRewards);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(staking)), rewardAmountOnContractBeforeClaim - accruedRewards, ABS_TOLERANCE
        );
        assertGe(rewardToken.balanceOf(address(staking)), rewardAmountOnContractBeforeClaim - accruedRewards);
    }

    function testFuzz_ClaimRewardsSeam(uint256 depositAmount, uint256 timePassed) public {
        depositAmount = bound(depositAmount, 1, 1_000_000_000 ether);
        timePassed = bound(timePassed, 1, 365 days);

        uint256 seamContractBalanceBefore = seam.balanceOf(address(staking));
        seam.mint(address(user), depositAmount);
        user.depositSeam(depositAmount);

        vm.warp(block.timestamp + timePassed);

        uint256 totalUserRewards = staking.getUserTotalRewardsForToken(address(user), address(seam), address(esSeam));
        user.claimRewardsSeam();

        uint256 accruedRewards = EMISSION_PER_SECOND * timePassed;
        assertEq(seam.balanceOf(address(user)), 0);
        assertEq(staking.getUserStakedBalance(address(user), address(seam)), depositAmount);
        assertEq(staking.getTotalStaked(address(seam)), depositAmount);

        assertApproxEqAbs(esSeam.balanceOf(address(user)), accruedRewards, ABS_TOLERANCE);
        assertLe(esSeam.balanceOf(address(user)), accruedRewards);
        assertApproxEqAbs(
            seam.balanceOf(address(staking)),
            seamContractBalanceBefore + depositAmount - totalUserRewards,
            ABS_TOLERANCE
        );
        assertGe(seam.balanceOf(address(staking)), seamContractBalanceBefore + depositAmount - totalUserRewards);
    }

    function testFuzz_Transfer(uint256 depositAmount, uint256 transferAmount, uint256 timeToPass) public {
        depositAmount = bound(depositAmount, 1, 1_000_000_000 ether);
        transferAmount = bound(transferAmount, 1, depositAmount);
        timeToPass = bound(timeToPass, 1, 365 days);

        address recipient = makeAddr("recepient");

        token.mint(address(user), depositAmount);
        user.deposit(depositAmount);

        vm.warp(block.timestamp + timeToPass);

        user.transfer(recipient, transferAmount);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(staking)), depositAmount);
        assertEq(staking.getUserStakedBalance(address(user), address(token)), depositAmount - transferAmount);
        assertEq(staking.getUserStakedBalance(recipient, address(token)), transferAmount);
        assertEq(staking.getTotalStaked(address(token)), depositAmount);

        uint256 accruedRewards = EMISSION_PER_SECOND * timeToPass;
        assertApproxEqAbs(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)), accruedRewards
        );
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)), accruedRewards
        );

        vm.warp(block.timestamp + timeToPass);
        uint256 newAccruedRewards = EMISSION_PER_SECOND * timeToPass;
        uint256 expectedAccruedRewardsUser1 =
            accruedRewards + newAccruedRewards * (depositAmount - transferAmount) / depositAmount;
        uint256 expectedAccruedRewardsUser2 = newAccruedRewards * transferAmount / depositAmount;

        assertApproxEqAbs(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)),
            expectedAccruedRewardsUser1,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserTotalRewardsForToken(address(user), address(token), address(rewardToken)),
            expectedAccruedRewardsUser1
        );
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)), accruedRewards
        );

        assertApproxEqAbs(
            staking.getUserTotalRewardsForToken(recipient, address(token), address(rewardToken)),
            expectedAccruedRewardsUser2,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserTotalRewardsForToken(recipient, address(token), address(rewardToken)),
            expectedAccruedRewardsUser2
        );
        assertEq(staking.getUserAccruedRewardsForToken(recipient, address(token), address(rewardToken)), 0);
    }
}
