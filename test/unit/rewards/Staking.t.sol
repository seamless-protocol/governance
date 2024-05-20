// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Staking} from "src/rewards/Staking.sol";
import {IStaking} from "src/interfaces/IStaking.sol";
import {User} from "../../scenarios/rewards/User.sol";
import {RewardTokenData, RewardTokenConfig} from "../../../src/types/DataTypes.sol";
import {EscrowSeam} from "../../../src/EscrowSeam.sol";
import {StakedToken} from "src/rewards/StakedToken.sol";

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

        StakedToken stakedTokenImplementation = new StakedToken();
        staking.setStakedTokenImplementation(address(stakedTokenImplementation));

        user = new User(token, seam, staking);

        staking.startStaking(address(token));
        staking.startStaking(address(seam));
        staking.configureRewardToken(
            address(token), address(rewardToken), RewardTokenConfig(0, type(uint256).max, EMISSION_PER_SECOND)
        );
        staking.configureRewardToken(
            address(seam), address(esSeam), RewardTokenConfig(0, type(uint256).max, EMISSION_PER_SECOND)
        );
        rewardToken.mint(address(staking), type(uint256).max);
        seam.mint(address(staking), type(uint256).max / 2);
    }

    function testFuzz_StartStaking(address newToken) public {
        vm.assume(newToken != address(token) && newToken != address(seam));
        staking.startStaking(newToken);

        assertEq(staking.getStakingTokens().length, 3);
        assertEq(staking.getStakingTokens()[2], newToken);
        assertEq(staking.getRewardTokens(newToken).length, 0);
        assertNotEq(staking.getStakedToken(newToken), address(0));

        RewardTokenConfig memory rewardTokenConfig = staking.getRewardTokenConfig(newToken, address(rewardToken));
        assertEq(rewardTokenConfig.startTimestamp, 0);
        assertEq(rewardTokenConfig.endTimestamp, 0);
        assertEq(rewardTokenConfig.emissionPerSecond, 0);
    }

    function testFuzz_StartStaking_RevertStakingTokenAlreadyAdded(address newToken) public {
        vm.assume(newToken != address(token) && newToken != address(seam));
        staking.startStaking(newToken);

        vm.expectRevert(IStaking.StakingAlreadyStarted.selector);
        staking.startStaking(newToken);
    }

    function testFuzz_ConfigureRewardToken(
        address asset,
        uint256 emissionPerSecond1,
        uint256 startTimestamp1,
        uint256 endTimestamp1,
        uint256 emissionPerSecond2,
        uint256 startTimestamp2,
        uint256 endTimestamp2
    ) public {
        staking.configureRewardToken(
            address(token), asset, RewardTokenConfig(startTimestamp1, endTimestamp1, emissionPerSecond1)
        );
        RewardTokenConfig memory rewardTokenConfig = staking.getRewardTokenConfig(address(token), asset);
        assertEq(rewardTokenConfig.startTimestamp, startTimestamp1);
        assertEq(rewardTokenConfig.endTimestamp, endTimestamp1);
        assertEq(rewardTokenConfig.emissionPerSecond, emissionPerSecond1);

        RewardTokenData memory rewardTokenData = staking.getRewardTokenData(address(token), asset);
        assertEq(rewardTokenData.rewardPerStakedToken, 0);
        assertEq(rewardTokenData.lastUpdatedTimestamp, 0);

        staking.configureRewardToken(
            address(token), asset, RewardTokenConfig(startTimestamp2, endTimestamp2, emissionPerSecond2)
        );
        RewardTokenConfig memory rewardTokenConfig2 = staking.getRewardTokenConfig(address(token), asset);
        assertEq(rewardTokenConfig2.startTimestamp, startTimestamp2);
        assertEq(rewardTokenConfig2.endTimestamp, endTimestamp2);
        assertEq(rewardTokenConfig2.emissionPerSecond, emissionPerSecond2);

        rewardTokenData = staking.getRewardTokenData(address(token), asset);
        assertEq(rewardTokenData.rewardPerStakedToken, 0);
        assertEq(rewardTokenData.lastUpdatedTimestamp, block.timestamp);
    }

    function testFuzz_ConfigureRewardToken_RevertAsetNotWhitelisted(
        address stakingAsset,
        address rewardAsset,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 emissionPerSecond
    ) public {
        vm.assume(stakingAsset != address(token) && stakingAsset != address(seam));
        vm.expectRevert(IStaking.StakingNotStarted.selector);
        staking.configureRewardToken(
            stakingAsset, rewardAsset, RewardTokenConfig(startTimestamp, endTimestamp, emissionPerSecond)
        );
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
        _validateTotalRewards(
            address(token), address(rewardToken), address(user), totalAccruedRewards, totalAccruedRewards
        );
    }

    function test_DepositRewardNotStarted() public {
        uint256 startTimestamp = block.timestamp + 1 days;
        uint256 endTimestamp = startTimestamp + 3 days;

        staking.configureRewardToken(
            address(token), address(rewardToken), RewardTokenConfig(startTimestamp, endTimestamp, EMISSION_PER_SECOND)
        );

        uint256 amount = 13.23414 ether;
        token.mint(address(user), amount);
        user.deposit(amount);

        assertEq(staking.getTotalStaked(address(token)), amount);
        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(staking)), amount);
        assertEq(staking.getUserStakedBalance(address(user), address(token)), amount);

        uint256 timeToPassInRewardProgram = 1 days;
        vm.warp(startTimestamp + timeToPassInRewardProgram);
        uint256 accruedRewards = timeToPassInRewardProgram * EMISSION_PER_SECOND;

        _validateTotalRewards(address(token), address(rewardToken), address(user), accruedRewards, accruedRewards);

        token.mint(address(user), amount);
        user.deposit(amount);

        assertEq(staking.getTotalStaked(address(token)), 2 * amount);
        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(staking)), 2 * amount);
        assertEq(staking.getUserStakedBalance(address(user), address(token)), 2 * amount);

        _validateTotalRewards(address(token), address(rewardToken), address(user), accruedRewards, accruedRewards);

        uint256 timeToPassAfterRewardsProgram = 2 days;
        vm.warp(endTimestamp + timeToPassAfterRewardsProgram);
        uint256 totalProgramRewards = (endTimestamp - startTimestamp) * EMISSION_PER_SECOND;

        _validateTotalRewards(
            address(token), address(rewardToken), address(user), totalProgramRewards, totalProgramRewards
        );

        token.mint(address(user), amount);
        user.deposit(amount);

        _validateTotalRewards(
            address(token), address(rewardToken), address(user), totalProgramRewards, totalProgramRewards
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
        _validateTotalRewards(address(token), address(rewardToken), address(user), accruedRewards, accruedRewards);
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
        _validateTotalRewards(address(token), address(rewardToken), address(user), accruedRewards, accruedRewards);

        vm.warp(block.timestamp + timeToPass);
        uint256 newAccruedRewards = EMISSION_PER_SECOND * timeToPass;
        uint256 expectedAccruedRewardsUser1 =
            accruedRewards + newAccruedRewards * (depositAmount - transferAmount) / depositAmount;
        uint256 expectedAccruedRewardsUser2 = newAccruedRewards * transferAmount / depositAmount;

        _validateTotalRewards(
            address(token),
            address(rewardToken),
            address(user),
            expectedAccruedRewardsUser1,
            accruedRewards + newAccruedRewards
        );

        _validateTotalRewards(
            address(token),
            address(rewardToken),
            recipient,
            expectedAccruedRewardsUser2,
            accruedRewards + newAccruedRewards
        );
    }

    function _validateTotalRewards(
        address asset,
        address rewardAsset,
        address account,
        uint256 userExpectedRewards,
        uint256 totalDistributedRewards
    ) private {
        assertApproxEqAbs(
            staking.getUserTotalRewardsForToken(address(account), address(asset), address(rewardAsset)),
            userExpectedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserTotalRewardsForToken(address(account), address(asset), address(rewardAsset)),
            totalDistributedRewards
        );
    }

    function _validateAccruedRewards(
        address asset,
        address rewardAsset,
        address account,
        uint256 expctedAccruedRewards,
        uint256 totalDistributedRewards
    ) private {
        assertApproxEqAbs(
            staking.getUserAccruedRewardsForToken(address(account), address(asset), address(rewardAsset)),
            expctedAccruedRewards,
            ABS_TOLERANCE
        );
        assertLe(
            staking.getUserAccruedRewardsForToken(address(account), address(asset), address(rewardAsset)),
            totalDistributedRewards
        );
    }
}
