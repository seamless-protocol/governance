// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakedToken} from "src/rewards/StakedToken.sol";
import {IStakedToken} from "src/interfaces/IStakedToken.sol";
import {User} from "../../scenarios/rewards/User.sol";
import {StakedTokenStorage as Storage} from "../../../src/storage/StakedTokenStorage.sol";

contract StakedTokenTest is Test {
    uint256 public constant ABS_TOLERANCE = 3 wei;
    uint256 public constant EMISSION_PER_SECOND = 10000 wei;

    ERC20Mock public token = new ERC20Mock();
    ERC20Mock public rewardToken = new ERC20Mock();

    StakedToken public stakedToken;

    User public user;

    function setUp() public {
        StakedToken stakedTokenImplementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(stakedTokenImplementation),
            abi.encodeWithSelector(StakedToken.initialize.selector, address(token), "Staked Token", "ST", address(this))
        );

        stakedToken = StakedToken(address(proxy));
        user = new User(token, stakedToken);

        stakedToken.configureRewardToken(address(rewardToken), EMISSION_PER_SECOND);
        rewardToken.mint(address(stakedToken), type(uint256).max);
    }

    function testFuzz_Deposit(uint256 amount1, uint256 amount2, uint256 timePassed) public {
        amount1 = bound(amount1, 1, 1_000_000_000 ether);
        amount2 = bound(amount2, 1, 1_000_000_000 ether);
        timePassed = bound(timePassed, 1, 365 days);

        token.mint(address(user), amount1);
        user.deposit(amount1);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(stakedToken)), amount1);
        assertEq(stakedToken.balanceOf(address(user)), amount1);
        assertEq(stakedToken.totalSupply(), amount1);
        assertEq(stakedToken.getUserTotalRewardsForToken(address(user), address(rewardToken)), 0);
        assertEq(stakedToken.getUserAccruedRewards(address(user), address(rewardToken)), 0);

        Storage.RewardTokenData memory rewardTokenData = stakedToken.getRewardTokenData(address(rewardToken));

        assertEq(rewardTokenData.rewardPerStakedToken, 0);
        assertEq(rewardTokenData.lastUpdatedTimestamp, block.timestamp);

        vm.warp(block.timestamp + timePassed);

        token.mint(address(user), amount2);
        user.deposit(amount2);

        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(stakedToken)), amount1 + amount2);
        assertEq(stakedToken.balanceOf(address(user)), amount1 + amount2);
        assertEq(stakedToken.totalSupply(), amount1 + amount2);

        uint256 totalAccruedRewards = EMISSION_PER_SECOND * timePassed;
        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(address(user), address(rewardToken)),
            totalAccruedRewards,
            ABS_TOLERANCE
        );
        assertApproxEqAbs(
            stakedToken.getUserAccruedRewards(address(user), address(rewardToken)), totalAccruedRewards, ABS_TOLERANCE
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
        assertEq(token.balanceOf(address(stakedToken)), depositAmount - withdrawAmount);
        assertEq(stakedToken.balanceOf(address(user)), depositAmount - withdrawAmount);
        assertEq(stakedToken.totalSupply(), depositAmount - withdrawAmount);

        uint256 accruedRewards = EMISSION_PER_SECOND * timePassed;
        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(address(user), address(rewardToken)), accruedRewards, ABS_TOLERANCE
        );
        assertApproxEqAbs(
            stakedToken.getUserAccruedRewards(address(user), address(rewardToken)), accruedRewards, ABS_TOLERANCE
        );
    }

    function testFuzz_ClaimRewards(uint256 depositAmount, uint256 timePassed) public {
        depositAmount = bound(depositAmount, 1, 1_000_000_000 ether);
        timePassed = bound(timePassed, 1, 365 days);

        token.mint(address(user), depositAmount);
        user.deposit(depositAmount);

        vm.warp(block.timestamp + timePassed);

        uint256 rewardAmountOnContractBeforeClaim = rewardToken.balanceOf(address(stakedToken));
        user.claimRewards();

        uint256 accruedRewards = EMISSION_PER_SECOND * timePassed;
        assertEq(token.balanceOf(address(user)), 0);
        assertEq(token.balanceOf(address(stakedToken)), depositAmount);
        assertEq(stakedToken.balanceOf(address(user)), depositAmount);
        assertEq(stakedToken.totalSupply(), depositAmount);

        assertEq(stakedToken.getUserTotalRewardsForToken(address(user), address(rewardToken)), 0);
        assertEq(stakedToken.getUserAccruedRewards(address(user), address(rewardToken)), 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(user)), accruedRewards, ABS_TOLERANCE);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(stakedToken)),
            rewardAmountOnContractBeforeClaim - accruedRewards,
            ABS_TOLERANCE
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
        assertEq(token.balanceOf(address(stakedToken)), depositAmount);
        assertEq(stakedToken.balanceOf(address(user)), depositAmount - transferAmount);
        assertEq(stakedToken.balanceOf(recipient), transferAmount);
        assertEq(stakedToken.totalSupply(), depositAmount);

        uint256 accruedRewards = EMISSION_PER_SECOND * timeToPass;
        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(address(user), address(rewardToken)), accruedRewards, ABS_TOLERANCE
        );
        assertApproxEqAbs(
            stakedToken.getUserAccruedRewards(address(user), address(rewardToken)), accruedRewards, ABS_TOLERANCE
        );

        vm.warp(block.timestamp + timeToPass);
        uint256 newAccruedRewards = EMISSION_PER_SECOND * timeToPass;
        uint256 expectedAccruedRewardsUser1 =
            accruedRewards + newAccruedRewards * (depositAmount - transferAmount) / depositAmount;
        uint256 expectedAccruedRewardsUser2 = newAccruedRewards * transferAmount / depositAmount;

        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(address(user), address(rewardToken)),
            expectedAccruedRewardsUser1,
            ABS_TOLERANCE
        );
        assertApproxEqAbs(
            stakedToken.getUserAccruedRewards(address(user), address(rewardToken)), accruedRewards, ABS_TOLERANCE
        );

        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(recipient, address(rewardToken)),
            expectedAccruedRewardsUser2,
            ABS_TOLERANCE
        );
        assertApproxEqAbs(stakedToken.getUserAccruedRewards(recipient, address(rewardToken)), 0, ABS_TOLERANCE);
    }

    // TODO: Copy this test to scenario tests and check if RewardTokenData is updated correctly
    function testFuzz_ConfigureRewardToken(address asset, uint256 emissionPerSecond1, uint256 emissionPerSecond2)
        public
    {
        stakedToken.configureRewardToken(asset, emissionPerSecond1);
        assertEq(stakedToken.getEmissionPerSecondForToken(asset), emissionPerSecond1);

        stakedToken.configureRewardToken(asset, emissionPerSecond2);
        assertEq(stakedToken.getEmissionPerSecondForToken(asset), emissionPerSecond2);
    }
}
