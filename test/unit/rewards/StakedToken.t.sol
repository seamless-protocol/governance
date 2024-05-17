// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Staking} from "src/rewards/Staking.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {User} from "../../scenarios/rewards/User.sol";
import {RewardTokenData} from "../../../src/types/DataTypes.sol";

contract StakingTest is Test {
    uint256 public constant ABS_TOLERANCE = 3 wei;
    uint256 public constant EMISSION_PER_SECOND = 10000 wei;

    ERC20Mock public token = new ERC20Mock();
    ERC20Mock public rewardToken = new ERC20Mock();

    Staking public staking;

    User public user;

    function setUp() public {
        Staking stakingImplementation = new Staking();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(stakingImplementation), abi.encodeWithSelector(Staking.initialize.selector, address(this))
        );

        staking = Staking(address(proxy));
        user = new User(token, staking);

        staking.addStakingToken(address(token));
        staking.configureRewardToken(address(token), address(rewardToken), EMISSION_PER_SECOND);
        rewardToken.mint(address(staking), type(uint256).max);
    }

    function testFuzz_AddStakingToken(address newToken) public {
        vm.assume(newToken != address(token));
        staking.addStakingToken(newToken);

        assertEq(staking.getStakingTokens().length, 2);
        assertEq(staking.getStakingTokens()[1], newToken);
        assertEq(staking.getEmissionPerSecond(newToken, address(rewardToken)), 0);
        assertEq(staking.getRewardTokens(newToken).length, 0);
        assertNotEq(staking.getStakedToken(newToken), address(0));
    }

    function testFuzz_AddStakingToken_RevertStakingTokenAlreadyAdded(address newToken) public {
        vm.assume(newToken != address(token));
        staking.addStakingToken(newToken);

        vm.expectRevert(IStaking.StakingTokenAlreadyAdded.selector);
        staking.addStakingToken(newToken);
    }

    function testFuzz_RemoveStakingToken(address newToken, uint256 emissionPerSecond) public {
        vm.assume(newToken != address(token));
        staking.addStakingToken(newToken);
        staking.configureRewardToken(newToken, address(rewardToken), emissionPerSecond);

        staking.removeStakingToken(newToken);

        assertEq(staking.getStakingTokens().length, 1);
        assertEq(staking.getEmissionPerSecond(newToken, address(rewardToken)), emissionPerSecond);
        assertEq(staking.getRewardTokens(newToken).length, 0);
        assertEq(staking.getStakedToken(newToken), address(0));
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
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            totalAccruedRewards,
            ABS_TOLERANCE
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
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
        );
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
        assertApproxEqAbs(
            rewardToken.balanceOf(address(staking)), rewardAmountOnContractBeforeClaim - accruedRewards, ABS_TOLERANCE
        );
    }

    function testFuzz_Transfer(uint256 depositAmount, uint256 transferAmount, uint256 timeToPass, address recipient)
        public
    {
        vm.assume(recipient != address(0));
        depositAmount = bound(depositAmount, 1, 1_000_000_000 ether);
        transferAmount = bound(transferAmount, 1, depositAmount);
        timeToPass = bound(timeToPass, 1, 365 days);

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
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
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
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(user), address(token), address(rewardToken)),
            accruedRewards,
            ABS_TOLERANCE
        );

        assertApproxEqAbs(
            staking.getUserTotalRewardsForToken(recipient, address(token), address(rewardToken)),
            expectedAccruedRewardsUser2,
            ABS_TOLERANCE
        );
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(recipient, address(token), address(rewardToken)), 0, ABS_TOLERANCE
        );
    }

    // TODO: Copy this test to scenario tests and check if RewardTokenData is updated correctly
    function testFuzz_ConfigureRewardToken(address asset, uint256 emissionPerSecond1, uint256 emissionPerSecond2)
        public
    {
        staking.configureRewardToken(address(token), asset, emissionPerSecond1);
        assertEq(staking.getEmissionPerSecond(address(token), asset), emissionPerSecond1);

        staking.configureRewardToken(address(token), asset, emissionPerSecond2);
        assertEq(staking.getEmissionPerSecond(address(token), asset), emissionPerSecond2);
    }
}
