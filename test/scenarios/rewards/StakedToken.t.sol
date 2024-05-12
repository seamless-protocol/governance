// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakedToken} from "src/rewards/StakedToken.sol";
import {IStakedToken} from "src/interfaces/IStakedToken.sol";
import {User} from "./User.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract StakedTokenTest is Test {
    uint256 public constant ABS_TOLERANCE = 3 wei;

    ERC20Mock public token = new ERC20Mock();
    ERC20Mock public rewardToken = new ERC20Mock();

    StakedToken public stakedToken;

    User public user1;
    User public user2;
    User public user3;

    function setUp() public {
        StakedToken stakedTokenImplementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(stakedTokenImplementation),
            abi.encodeWithSelector(StakedToken.initialize.selector, address(token), address(this))
        );

        stakedToken = StakedToken(address(proxy));

        token.mint(address(this), 100 ether);
        rewardToken.mint(address(proxy), 1000000000 ether);

        user1 = new User(token, stakedToken);
        user2 = new User(token, stakedToken);
        user3 = new User(token, stakedToken);

        token.mint(address(user1), 1_000_000 ether);
        token.mint(address(user2), 1_000_000 ether);
        token.mint(address(user3), 1_000_000 ether);
    }

    function testDeploy() public {
        assertEq(stakedToken.getStakedToken(), address(token));
        assertEq(stakedToken.owner(), address(this));
        assertEq(stakedToken.getRewardTokens().length, 0);
    }

    /*
    Scenario: 
    - Configure the reward token
    - User deposits the staked token
    - User deposits again after some time
    - User deposits again after some time

    Expected:
    - Users accrued rewards should proportionally increase based on passed time between deposits
    */
    function testDeposit_OnlyOneStaker() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        uint256[] memory emissionPerSecond = new uint256[](1);
        emissionPerSecond[0] = 1 ether;

        stakedToken.addRewardTokens(rewardTokens, emissionPerSecond);

        uint256 amount = 10 ether;
        token.approve(address(stakedToken), type(uint256).max);
        stakedToken.deposit(amount, address(this));

        uint256 timeToPass = 100;
        vm.warp(block.timestamp + timeToPass);

        stakedToken.deposit(amount, address(this));

        uint256 expectedAccruedRewards = timeToPass * emissionPerSecond[0];
        assertEq(stakedToken.getUserAccruedRewards(address(this), address(rewardToken)), expectedAccruedRewards);

        timeToPass = 1000;
        vm.warp(block.timestamp + timeToPass);

        stakedToken.deposit(amount, address(this));

        expectedAccruedRewards += timeToPass * emissionPerSecond[0];
        assertEq(stakedToken.getUserAccruedRewards(address(this), address(rewardToken)), expectedAccruedRewards);
    }

    /*
    Scenario:
    - Configure the reward token
    - User1 deposits the tokens
    - User2 deposits the tokens
    - User3 deposits the tokens
    - User1 deposits again
    - User3 deposits again
    - User2 deposits again
    - User3 deposits again
    - User1 deposits again
    - User2 deposits again

    Expected:
    - Users accrued rewards should proportionally increase based on passed time between deposits
    - Users staked amount should be correctly updated after each deposit
    */
    function testDeposti_MulipleStakers() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        uint256[] memory emissionPerSecond = new uint256[](1);
        emissionPerSecond[0] = 1000;

        stakedToken.addRewardTokens(rewardTokens, emissionPerSecond);

        uint256 expectedUser1TotalStaked;
        uint256 expectedUser2TotalStaked;
        uint256 expectedUser3TotalStaked;
        uint256 expectedUser1AccruedRewards;
        uint256 expectedUser2AccruedRewards;
        uint256 expectedUser3AccruedRewards;

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;

        uint256 expectedTotalStaked = expectedUser1TotalStaked + expectedUser2TotalStaked + expectedUser3TotalStaked;
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(0, 0, 0);

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        expectedUser1AccruedRewards += timeToPass * emissionPerSecond[0];

        amount = 20 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;

        expectedTotalStaked += amount;
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, 0, 0);

        timeToPass = 8_000_000;
        vm.warp(block.timestamp + timeToPass);

        uint256 newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += newRewards * expectedUser2TotalStaked / expectedTotalStaked;

        amount = 50 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 765_241;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 100 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 200 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 143_420_011;
        amount = 1_000 ether;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 500 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 100_000_124;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 1_000 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 1_000 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
    }

    /*
    Scenario:
    - Configure the reward token
    - User1 deposits the tokens
    - User1 withdraws the tokens
    - User1 deposits the tokens
    - User1 withdraws all the tokens
    - Some time passes and user is not earning rewards since he withdrew everything
    - User deposits again
    - Some time passes and user starts earning rewards again but only from timestamp of the last deposit

    Expected:
    - Accrued rewards should be correctly updated after each deposit and withdrawal
    - User should not earn rewards after withdrawing everything
    - User should start earning rewards again after depositing
    - User's total staked amount should be correctly updated after each deposit and withdrawal
    */
    function testWithdraw_OnlyOneUser() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        uint256[] memory emissionPerSecond = new uint256[](1);
        emissionPerSecond[0] = 1000;

        stakedToken.addRewardTokens(rewardTokens, emissionPerSecond);

        uint256 expectedUserTotalStaked;
        uint256 expectedUserAccruedRewards;

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(0, 0, 0);

        uint256 timeToPass = 982_123;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond[0];

        amount = 9.234 ether;
        user1.withdraw(amount);
        expectedUserTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 1234_213_128;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond[0];

        amount = 1.8888 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond[0];

        user1.withdraw(expectedUserTotalStaked);
        expectedUserTotalStaked = 0;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        amount = 1 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 154_000_451;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond[0];

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);
    }

    /*
    Scenario:
    - Configure the reward token
    - User1 deposits the tokens
    - User2 deposits the tokens
    - User1 does partial withdrawal
    - User3 deposits the tokens
    - User1 deposits the tokens
    - User2 does partial withdrawal
    - User1 does full withdrawal
    - User2 does full withdrawal
    - User3 does full withdrawal
    - Time passes and no rewards are accrued by any user

    Expected:
    - Users accrued rewards should be correctly updated after each deposit and withdrawal
    - Users staked amount should be correctly updated after each deposit and withdrawal
    - Users should not earn rewards after withdrawing everything
    - User's staked amount should be correctly updated after each deposit and withdrawal
    - Total staked amount should be correctly updated after each deposit and withdrawal
    */
    function testDepositAndWithdraw_MultipleUsers() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        uint256[] memory emissionPerSecond = new uint256[](1);
        emissionPerSecond[0] = 1000;

        stakedToken.addRewardTokens(rewardTokens, emissionPerSecond);

        uint256 expectedUser1TotalStaked;
        uint256 expectedUser2TotalStaked;
        uint256 expectedUser3TotalStaked;
        uint256 expectedTotalStaked;
        uint256 expectedUser1AccruedRewards;
        uint256 expectedUser2AccruedRewards;
        uint256 expectedUser3AccruedRewards;

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(0, 0, 0);

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUser1AccruedRewards = timeToPass * emissionPerSecond[0];

        amount = 20 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 8_000_000;
        vm.warp(block.timestamp + timeToPass);
        uint256 newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        amount = 5.76913 ether;
        user1.withdraw(amount);
        expectedUser1TotalStaked -= amount;
        expectedTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 765_241;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        amount = 50 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_234_567;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 100 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 145_234_111_327;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 1.23455 ether;
        user2.withdraw(amount);
        expectedUser2TotalStaked -= amount;
        expectedTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user1.withdraw(expectedUser1TotalStaked);
        expectedUser1TotalStaked = 0;
        expectedTotalStaked = expectedUser2TotalStaked + expectedUser3TotalStaked;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_000_001;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user2.withdraw(expectedUser2TotalStaked);
        expectedUser2TotalStaked = 0;
        expectedTotalStaked = expectedUser3TotalStaked;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_245_678;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user3.withdraw(expectedUser3TotalStaked);
        expectedUser3TotalStaked = 0;
        expectedTotalStaked = 0;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 17;
        vm.warp(block.timestamp + timeToPass);

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
    }

    /*
    Scenario:
    - Configure the reward token
    - User1 deposits the tokens
    - User1 claims the rewards
    - User1 deposits the tokens
    - User1 deposits the tokens
    - User1 claims the rewards
    - User1 does partial withdrawal
    - User1 claims the rewards
    - User1 withdraws all the tokens
    - User1 claims the rewards
    - Some time passes and no rewards are accrued

    Expected:
    - Users accrued rewards should be correctly updated after each deposit, withdrawal and claim
    - Users staked amount should be correctly updated after each deposit and withdrawal
    - Users should not earn rewards after withdrawing everything
    */
    function testClaimReward_OnlyOneUser() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        uint256[] memory emissionPerSecond = new uint256[](1);
        emissionPerSecond[0] = 1000;

        stakedToken.addRewardTokens(rewardTokens, emissionPerSecond);

        uint256 expectedUserTotalStaked;
        uint256 expectedUserAccruedRewards;

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(0, 0, 0);

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond[0];

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        user1.claimRewards();

        _validateAccruedRewards(0, 0, 0);
        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(user1)), expectedUserAccruedRewards, ABS_TOLERANCE);

        timeToPass = 1_000_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond[0];

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        amount = 20 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond[0];

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        amount = 50 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 1_000_244_444_123_444;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond[0];

        uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        user1.claimRewards();

        _validateAccruedRewards(0, 0, 0);
        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUserAccruedRewards, ABS_TOLERANCE
        );

        timeToPass = 123_456_679_865_111_432;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond[0];

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        amount = 5.76913 ether;
        user1.withdraw(amount);
        expectedUserTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond[0];

        user1.withdraw(expectedUserTotalStaked);
        expectedUserTotalStaked = 0;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        user1.claimRewards();

        _validateAccruedRewards(0, 0, 0);
        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUserAccruedRewards, ABS_TOLERANCE
        );

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(0, 0, 0);
    }

    /*
    Scenario:
    - Configure the reward token
    - User1 deposits the tokens
    - User2 deposits the tokens
    - User3 deposits the tokens
    - User1 claims the rewards
    - User2 does partial withdrawal
    - User3 withdraws all the tokens
    - User3 claims the rewards
    - User3 deposits the tokens
    - User2 claims the rewards
    - User1 withdraws all the tokens
    - User1 claims the rewards
    - Some time passes and no rewards are accrued
    - User2 claims the rewards
    - User2 withdraws all the tokens
    - User2 claims the rewards
    - Some time passes and no rewards are accrued
    - User3 withdraws all the tokens
    - User3 claims the rewards
    - Some time passes and no rewards are accrued by any user
    */
    function testClaimRewards_MultipleUsers() public {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);

        uint256[] memory emissionPerSecond = new uint256[](1);
        emissionPerSecond[0] = 1000;

        stakedToken.addRewardTokens(rewardTokens, emissionPerSecond);

        uint256 expectedTotalStaked;
        uint256 expectedUser1TotalStaked;
        uint256 expectedUser2TotalStaked;
        uint256 expectedUser3TotalStaked;
        uint256 expectedUser1AccruedRewards;
        uint256 expectedUser2AccruedRewards;
        uint256 expectedUser3AccruedRewards;

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        expectedUser1AccruedRewards = timeToPass * emissionPerSecond[0];
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        amount = 20 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 111_222_213_445_796_421;
        vm.warp(block.timestamp + timeToPass);

        uint256 newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        amount = 50 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        user1.claimRewards();

        _validateAccruedRewards(0, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUser1AccruedRewards, ABS_TOLERANCE
        );
        expectedUser1AccruedRewards = 0;

        timeToPass = 435_333_222_777_111_111_111;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 5.76913 ether;
        user2.withdraw(amount);
        expectedUser2TotalStaked -= amount;
        expectedTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        timeToPass = 234_124_123_123_123_123;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user3.withdraw(expectedUser3TotalStaked);
        expectedTotalStaked -= expectedUser3TotalStaked;
        expectedUser3TotalStaked = 0;

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        timeToPass = 499_999_999_999_999_999;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user3));
        user3.claimRewards();

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, 0);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user3)), rewardTokenBalanceBefore + expectedUser3AccruedRewards, ABS_TOLERANCE
        );
        expectedUser3AccruedRewards = 0;

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        amount = 100 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user2));
        user2.claimRewards();

        _validateAccruedRewards(expectedUser1AccruedRewards, 0, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user2)), rewardTokenBalanceBefore + expectedUser2AccruedRewards, ABS_TOLERANCE
        );
        expectedUser2AccruedRewards = 0;

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user1.withdraw(expectedUser1TotalStaked);
        expectedTotalStaked -= expectedUser1TotalStaked;
        expectedUser1TotalStaked = 0;

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // User 1 claims rewards

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        user1.claimRewards();

        _validateAccruedRewards(0, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUser1AccruedRewards, ABS_TOLERANCE
        );
        expectedUser1AccruedRewards = 0;

        // Some time passes

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // User 2 claims rewards

        timeToPass = 2134;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user2));
        user2.claimRewards();

        _validateAccruedRewards(expectedUser1AccruedRewards, 0, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user2)), rewardTokenBalanceBefore + expectedUser2AccruedRewards, ABS_TOLERANCE
        );
        expectedUser2AccruedRewards = 0;

        // User2 withdraws all the tokens

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        user2.withdraw(expectedUser2TotalStaked);
        expectedTotalStaked -= expectedUser2TotalStaked;
        expectedUser2TotalStaked = 0;

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // User2 claims rewards

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser3AccruedRewards += newRewards;
        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user2));
        user2.claimRewards();

        _validateAccruedRewards(0, 0, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user2)), rewardTokenBalanceBefore + expectedUser2AccruedRewards, ABS_TOLERANCE
        );
        expectedUser2AccruedRewards = 0;

        // Some time passes

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond[0];
        expectedUser3AccruedRewards += newRewards;
        _validateAccruedRewards(0, 0, expectedUser3AccruedRewards);

        // User3 withdraws all the tokens

        user3.withdraw(expectedUser3TotalStaked);
        expectedTotalStaked = 0;
        expectedUser3TotalStaked = 0;

        _validateAccruedRewards(0, 0, expectedUser3AccruedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // User3 claims rewards

        timeToPass = 123;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, expectedUser3AccruedRewards);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user3));
        user3.claimRewards();

        _validateAccruedRewards(0, 0, 0);
        _validateUsersStakedAmounts(0, 0, 0);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user3)), rewardTokenBalanceBefore + expectedUser3AccruedRewards, ABS_TOLERANCE
        );

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 0, 0);
        _validateUsersStakedAmounts(0, 0, 0);
    }

    function _validateAccruedRewards(
        uint256 expectedUser1AccruedRewards,
        uint256 expectedUser2AccruedRewards,
        uint256 expectedUser3AccruedRewards
    ) internal {
        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(address(user1), address(rewardToken)),
            expectedUser1AccruedRewards,
            ABS_TOLERANCE
        );
        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(address(user2), address(rewardToken)),
            expectedUser2AccruedRewards,
            ABS_TOLERANCE
        );
        assertApproxEqAbs(
            stakedToken.getUserTotalRewardsForToken(address(user3), address(rewardToken)),
            expectedUser3AccruedRewards,
            ABS_TOLERANCE
        );
    }

    function _validateUsersStakedAmounts(
        uint256 expectedUser1TotalStaked,
        uint256 expectedUser2TotalStaked,
        uint256 expectedUser3TotalStaked
    ) internal {
        assertEq(stakedToken.getUserTotalStaked(address(user1)), expectedUser1TotalStaked);
        assertEq(stakedToken.getUserTotalStaked(address(user2)), expectedUser2TotalStaked);
        assertEq(stakedToken.getUserTotalStaked(address(user3)), expectedUser3TotalStaked);

        uint256 expectedTotalStaked = expectedUser1TotalStaked + expectedUser2TotalStaked + expectedUser3TotalStaked;
        assertEq(stakedToken.getTotalStaked(), expectedTotalStaked);
        assertEq(token.balanceOf(address(stakedToken)), expectedTotalStaked);
    }
}
