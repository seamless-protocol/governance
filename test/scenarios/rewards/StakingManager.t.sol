// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingManager} from "src/rewards/StakingManager.sol";
import {IStakingManager} from "src/interfaces/IStakingManager.sol";
import {User} from "./User.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {RewardTokenConfig} from "src/types/DataTypes.sol";
import {StakedToken} from "src/rewards/StakedToken.sol";

contract StakingManagerTest is Test {
    uint256 public constant ABS_TOLERANCE = 4 wei;

    uint256 public emissionPerSecond = 10000 wei;

    ERC20Mock public seam = new ERC20Mock();
    ERC20Mock public esSeam = new ERC20Mock();
    ERC20Mock public token = new ERC20Mock();
    ERC20Mock public rewardToken = new ERC20Mock();

    StakingManager public staking;

    User public user1;
    User public user2;
    User public user3;

    function setUp() public {
        StakingManager stakingImplementation = new StakingManager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(stakingImplementation),
            abi.encodeWithSelector(StakingManager.initialize.selector, address(seam), address(esSeam), address(this))
        );
        staking = StakingManager(address(proxy));

        StakedToken stakedTokenImplementation = new StakedToken();
        staking.setStakedTokenImplementation(address(stakedTokenImplementation));

        token.mint(address(this), 100 ether);
        rewardToken.mint(address(proxy), 1000000000 ether);

        user1 = new User(token, ERC20Mock(address(0)), staking);
        user2 = new User(token, ERC20Mock(address(0)), staking);
        user3 = new User(token, ERC20Mock(address(0)), staking);

        token.mint(address(user1), 1_000_000 ether);
        token.mint(address(user2), 1_000_000 ether);
        token.mint(address(user3), 1_000_000 ether);

        staking.startStaking(address(token));
        staking.configureRewardToken(
            address(token),
            address(rewardToken),
            RewardTokenConfig({startTimestamp: 0, endTimestamp: type(uint256).max, emissionPerSecond: emissionPerSecond})
        );
    }

    function testDeploy() public {
        assertEq(staking.owner(), address(this));
        assertEq(staking.isStakingStarted(address(token)), true);
        assertNotEq(staking.getStakedToken(address(token)), address(0));
    }
    /*
     Scenario:
      - User deposits the staked token
      - User deposits again after some time
      - User deposits again after some time

     Expected:
      - Users accrued rewards should proportionally increase based on passed time between deposits
    */

    function testDeposit_OnlyOneStaker() public {
        // User deposits the staked token

        uint256 amount = 10 ether;
        user1.deposit(amount);

        // User deposits again after some time

        uint256 timeToPass = 100;
        vm.warp(block.timestamp + timeToPass);
        user1.deposit(amount);

        // Check that user's accrued rewards are correctly updated after iteactions

        uint256 expectedAccruedRewards = timeToPass * emissionPerSecond;
        _validateAccruedRewards(expectedAccruedRewards, 0, 0, expectedAccruedRewards);

        // User deposits again after some time

        timeToPass = 1000;
        vm.warp(block.timestamp + timeToPass);
        user1.deposit(amount);

        // Check that user's accrued rewards are correctly updated after iteactions

        expectedAccruedRewards += timeToPass * emissionPerSecond;
        _validateAccruedRewards(expectedAccruedRewards, 0, 0, expectedAccruedRewards);
    }

    /*
    Scenario:
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
    function testDeposit_MulipleStakers() public {
        uint256 expectedUser1TotalStaked;
        uint256 expectedUser2TotalStaked;
        uint256 expectedUser3TotalStaked;
        uint256 expectedUser1AccruedRewards;
        uint256 expectedUser2AccruedRewards;
        uint256 expectedUser3AccruedRewards;
        uint256 totalDistributedRewards;

        uint256 rewardEndTimestamp = block.timestamp + 123_132_134;
        staking.configureRewardToken(
            address(token),
            address(rewardToken),
            RewardTokenConfig({
                startTimestamp: block.timestamp,
                endTimestamp: rewardEndTimestamp,
                emissionPerSecond: emissionPerSecond
            })
        );

        // User1 deposits the tokens, check that his position and accrued rewards are correctly updated

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;

        uint256 expectedTotalStaked = expectedUser1TotalStaked + expectedUser2TotalStaked + expectedUser3TotalStaked;
        totalDistributedRewards = (block.timestamp - 1) * emissionPerSecond;
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(0, 0, 0, totalDistributedRewards);

        // Some time passes and user2 deposits the tokens, check that his position and accrued rewards are correctly updated

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        expectedUser1AccruedRewards += timeToPass * emissionPerSecond;

        amount = 20 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;

        expectedTotalStaked += amount;
        totalDistributedRewards = (block.timestamp - 1) * emissionPerSecond;
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(expectedUser1AccruedRewards, 0, 0, totalDistributedRewards);

        // Some time passes and user3 deposits the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 8_000_000;
        vm.warp(block.timestamp + timeToPass);

        uint256 newRewards = timeToPass * emissionPerSecond;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += newRewards * expectedUser2TotalStaked / expectedTotalStaked;

        amount = 50 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;
        totalDistributedRewards = (block.timestamp - 1) * emissionPerSecond;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user1 deposits again, check that his position and accrued rewards are correctly updated

        timeToPass = 765_241;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 100 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        timeToPass = rewardEndTimestamp - block.timestamp;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        // Reward program is expired, users should not earn anything from this moment
        emissionPerSecond = 0;

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user3 deposits again, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        amount = 200 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Admin changes emission per second, check that users accrued rewards are correctly updated

        emissionPerSecond = 10000;
        staking.configureRewardToken(
            address(token),
            address(rewardToken),
            RewardTokenConfig({
                startTimestamp: block.timestamp,
                endTimestamp: type(uint256).max,
                emissionPerSecond: emissionPerSecond
            })
        );

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // // Some time passes and user2 deposits again, check that his position and accrued rewards are correctly updated

        timeToPass = 143_420_011;
        amount = 1_000 ether;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;

        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user3 deposits again, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 500 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user1 deposits again, check that his position and accrued rewards are correctly updated

        timeToPass = 100_000_124;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 1_000 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user2 deposits again, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 1_000 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
    }

    /*
     Scenario:
     - User1 deposits the tokens
     - User1 withdraws the tokens
     - User1 deposits the tokens
     - User1 withdraws all the tokens
     - Some time passes and user is not earning rewards since he withdrew everything
     - User1 deposits the tokens
     - Some time passes and user starts earning rewards again but only from timestamp of the last deposit

     Expected:
     - Accrued rewards should be correctly updated after each deposit and withdrawal
     - User should not earn rewards after withdrawing everything
     - User should start earning rewards again after depositing
     - User's total staked amount should be correctly updated after each deposit and withdrawal
    */
    function testWithdraw_OnlyOneUser() public {
        uint256 expectedUserTotalStaked;
        uint256 expectedUserAccruedRewards;

        // User1 deposits the tokens, check that his position and accrued rewards are correctly updated, rewards should be 0

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(0, 0, 0, 0);

        // Some time passes and user1 withdraws the tokens, check that his position and accrued rewards are correctly updated

        uint256 timeToPass = 982_123;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond;

        amount = 9.234 ether;
        user1.withdraw(amount);
        expectedUserTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and user1 deposits the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 1234_213_128;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond;

        amount = 1.8888 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and user1 withdraws all the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond;

        user1.withdraw(expectedUserTotalStaked);
        expectedUserTotalStaked = 0;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and user is not earning rewards since he withdrew everything

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        amount = 1 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and user starts earning rewards again but only from timestamp of the last deposit

        timeToPass = 154_000_451;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);
    }

    /*
     Scenario:
     - User1 deposits the tokens
     - User2 deposits the tokens
     - User1 does partial withdrawal
     - User3 deposits the tokens
     - User1 deposits the tokens
     - User2 partialy transfers staked token to User3
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
        uint256 expectedTotalStaked;
        uint256 expectedUser1TotalStaked;
        uint256 expectedUser2TotalStaked;
        uint256 expectedUser3TotalStaked;
        uint256 expectedUser1AccruedRewards;
        uint256 expectedUser2AccruedRewards;
        uint256 expectedUser3AccruedRewards;
        uint256 totalDistributedRewards;

        uint256 rewardsEndAtTimestamp = block.timestamp + 12_000_000;

        staking.configureRewardToken(
            address(token),
            address(rewardToken),
            RewardTokenConfig({
                startTimestamp: block.timestamp,
                endTimestamp: rewardsEndAtTimestamp,
                emissionPerSecond: emissionPerSecond
            })
        );

        // User1 deposits the tokens, check that his position and accrued rewards are correctly updated, rewards should be 0

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(0, 0, 0, 0);

        // Some time passes and user2 deposits the tokens
        // Check that his position and accrued rewards are correctly updated, all rewards should go to user1

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUser1AccruedRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards = expectedUser1AccruedRewards;

        amount = 20 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        //Some time passes and user1 does partial withdrawal, check that his position and accrued rewards are correctly updated

        timeToPass = 8_000_000;
        vm.warp(block.timestamp + timeToPass);
        uint256 newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        amount = 5.76913 ether;
        user1.withdraw(amount);
        expectedUser1TotalStaked -= amount;
        expectedTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user3 deposits the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 765_241;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        amount = 50 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user1 deposits the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 1_234_567;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        timeToPass = rewardsEndAtTimestamp - block.timestamp;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Reward program is finished, users should not earn anything from this moment
        emissionPerSecond = 0;

        amount = 100 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user2 transfers staked token to user3, check that their positions and accrued rewards are correctly updated
        // Staked amount on user2 should decrease but should increase to user3

        timeToPass = 145_234_111_327;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;

        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 1.23455 ether;
        user2.transfer(address(user3), amount);
        expectedUser2TotalStaked -= amount;
        expectedUser3TotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Admin changes emission per second, check that users accrued rewards are correctly updated
        emissionPerSecond = 10000;
        staking.configureRewardToken(
            address(token),
            address(rewardToken),
            RewardTokenConfig({
                startTimestamp: block.timestamp,
                endTimestamp: type(uint256).max,
                emissionPerSecond: emissionPerSecond
            })
        );

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user1 does full withdrawal, check that his position and accrued rewards are correctly updated
        // User1 should not earn rewards after withdrawing everything

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user1.withdraw(expectedUser1TotalStaked);
        expectedUser1TotalStaked = 0;
        expectedTotalStaked = expectedUser2TotalStaked + expectedUser3TotalStaked;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user2 does full withdrawal, check that his position and accrued rewards are correctly updated
        // Rewards should increase only to user2 and user3 because user1 withdrew everything in previous step
        // User2 should not earn rewards after withdrawing everything

        timeToPass = 1_000_001;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user2.withdraw(expectedUser2TotalStaked);
        expectedUser2TotalStaked = 0;
        expectedTotalStaked = expectedUser3TotalStaked;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user3 does full withdrawal, check that his position and accrued rewards are correctly updated
        // Rewards should increase only to user3 because user1 and user2 withdrew everything in previous steps

        timeToPass = 1_245_678;
        vm.warp(block.timestamp + timeToPass);
        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user3.withdraw(expectedUser3TotalStaked);
        expectedUser3TotalStaked = 0;
        expectedTotalStaked = 0;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Time passes and no rewards are accrued by any user

        timeToPass = 17;
        vm.warp(block.timestamp + timeToPass);
        totalDistributedRewards += timeToPass * emissionPerSecond;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
    }

    /*
     Scenario:
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
        uint256 expectedUserTotalStaked;
        uint256 expectedUserAccruedRewards;

        // User1 deposits the tokens, check that his position and accrued rewards are correctly updated, rewards should be 0

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(0, 0, 0, 0);

        // Some time passes and user1 claims the rewards, check that his position and accrued rewards are correctly updated
        // After claiming current rewards should be 0 but reward token should be transfered on his wallet

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond;

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        user1.claimRewards();

        _validateAccruedRewards(0, 0, 0, 0);
        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        assertApproxEqAbs(rewardToken.balanceOf(address(user1)), expectedUserAccruedRewards, ABS_TOLERANCE);

        // Some time passes and user1 deposits the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond;

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        amount = 20 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and user1 deposits the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond;

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        amount = 50 ether;
        user1.deposit(amount);
        expectedUserTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and user1 claims the rewards, check that his position and accrued rewards are correctly updated
        // After claiming current rewards should be 0 but reward token should be transfered on his wallet

        timeToPass = 1_000_244_444_123_444;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond;

        uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        user1.claimRewards();

        _validateAccruedRewards(0, 0, 0, 0);
        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUserAccruedRewards, ABS_TOLERANCE
        );

        // Some time passes and user1 does partial withdrawal, check that his position and accrued rewards are correctly updated

        timeToPass = 123_456_679_865_111_432;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards = timeToPass * emissionPerSecond;

        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        amount = 5.76913 ether;
        user1.withdraw(amount);
        expectedUserTotalStaked -= amount;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and user1 does full withdrawal, check that his position and accrued rewards are correctly updated
        // User should not earn rewards after withdrawing everything even if he is only staker

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);
        expectedUserAccruedRewards += timeToPass * emissionPerSecond;

        user1.withdraw(expectedUserTotalStaked);
        expectedUserTotalStaked = 0;

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        // Some time passes and no new rewards are accrued, user1 claims old rewards

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(expectedUserAccruedRewards, 0, 0, expectedUserAccruedRewards);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        user1.claimRewards();

        _validateAccruedRewards(0, 0, 0, 0);
        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUserAccruedRewards, ABS_TOLERANCE
        );

        // Some time passes and no rewards are accrued and user has no position

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateUsersStakedAmounts(expectedUserTotalStaked, 0, 0);
        _validateAccruedRewards(0, 0, 0, 0);
    }

    /*
     Scenario:
      - User1 deposits the tokens
      - User2 deposits the tokens
      - User3 deposits the tokens
      - User1 claims the rewards
      - User2 partialy transfers staked token to User3
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
        uint256 expectedTotalStaked;
        uint256 expectedUser1TotalStaked;
        uint256 expectedUser2TotalStaked;
        uint256 expectedUser3TotalStaked;
        uint256 expectedUser1AccruedRewards;
        uint256 expectedUser2AccruedRewards;
        uint256 expectedUser3AccruedRewards;
        uint256 totalDistributedRewards;

        // User1 deposits the tokens, check that his position and accrued rewards are correctly updated, rewards should be 0

        uint256 amount = 10 ether;
        user1.deposit(amount);
        expectedUser1TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user2 deposits the tokens, check that his position and accrued rewards are correctly updated

        uint256 timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        expectedUser1AccruedRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards = expectedUser1AccruedRewards;
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        amount = 20 ether;
        user2.deposit(amount);
        expectedUser2TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user3 deposits the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 111_222_213_445_796_421;
        vm.warp(block.timestamp + timeToPass);

        uint256 newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        amount = 50 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user1 claims the rewards, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        user1.claimRewards();
        totalDistributedRewards -= rewardToken.balanceOf(address(user1)) - rewardTokenBalanceBefore;

        _validateAccruedRewards(0, expectedUser2AccruedRewards, expectedUser3AccruedRewards, totalDistributedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUser1AccruedRewards, ABS_TOLERANCE
        );
        expectedUser1AccruedRewards = 0;

        // Some time passes and user2 partially transfers staked token to user3, check that their positions and accrued rewards are correctly updated

        timeToPass = 435_333_222_777_111_111_111;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        amount = 5.76913 ether;
        user2.transfer(address(user3), amount);
        expectedUser2TotalStaked -= amount;
        expectedUser3TotalStaked += amount;

        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        // Some time passes and user3 withdraws all the tokens, check that his position and accrued rewards are correctly updated
        // User3 should not earn rewards after withdrawing everything

        timeToPass = 234_124_123_123_123_123;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user3.withdraw(expectedUser3TotalStaked);
        expectedTotalStaked -= expectedUser3TotalStaked;
        expectedUser3TotalStaked = 0;

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // Some time passes and user3 claims the rewards, check that his position and accrued rewards are correctly updated
        // User3 did not earn any new rewards after withdrawing, all rewards should be from previous step

        timeToPass = 499_999_999_999_999_999;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user3));
        user3.claimRewards();
        totalDistributedRewards -= rewardToken.balanceOf(address(user3)) - rewardTokenBalanceBefore;

        _validateAccruedRewards(expectedUser1AccruedRewards, expectedUser2AccruedRewards, 0, totalDistributedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user3)), rewardTokenBalanceBefore + expectedUser3AccruedRewards, ABS_TOLERANCE
        );
        expectedUser3AccruedRewards = 0;

        // Some time passes and user3 deposits again, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        amount = 100 ether;
        user3.deposit(amount);
        expectedUser3TotalStaked += amount;
        expectedTotalStaked += amount;

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // Some time passes and user2 claims the rewards, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user2));
        user2.claimRewards();
        totalDistributedRewards -= rewardToken.balanceOf(address(user2)) - rewardTokenBalanceBefore;

        _validateAccruedRewards(expectedUser1AccruedRewards, 0, expectedUser3AccruedRewards, totalDistributedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user2)), rewardTokenBalanceBefore + expectedUser2AccruedRewards, ABS_TOLERANCE
        );
        expectedUser2AccruedRewards = 0;

        // Some time passes and user1 withdraws all the tokens, check that his position and accrued rewards are correctly updated
        // User1 should not earn rewards after withdrawing everything

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser1AccruedRewards += Math.mulDiv(newRewards, expectedUser1TotalStaked, expectedTotalStaked);
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);

        user1.withdraw(expectedUser1TotalStaked);
        expectedTotalStaked -= expectedUser1TotalStaked;
        expectedUser1TotalStaked = 0;

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // Some time passes and user1 claims the rewards, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user1));
        user1.claimRewards();
        totalDistributedRewards -= rewardToken.balanceOf(address(user1)) - rewardTokenBalanceBefore;

        _validateAccruedRewards(0, expectedUser2AccruedRewards, expectedUser3AccruedRewards, totalDistributedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user1)), rewardTokenBalanceBefore + expectedUser1AccruedRewards, ABS_TOLERANCE
        );
        expectedUser1AccruedRewards = 0;

        // Some time passes and no rewards are accrued for user1, all new rewards are split between user2 and user3

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // Some time passes and user2 claims the rewards, check that his position and accrued rewards are correctly updated

        timeToPass = 2134;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user2));
        user2.claimRewards();
        totalDistributedRewards -= rewardToken.balanceOf(address(user2)) - rewardTokenBalanceBefore;

        _validateAccruedRewards(expectedUser1AccruedRewards, 0, expectedUser3AccruedRewards, totalDistributedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user2)), rewardTokenBalanceBefore + expectedUser2AccruedRewards, ABS_TOLERANCE
        );
        expectedUser2AccruedRewards = 0;

        // Some time passes and user2 withdraws all the tokens, check that his position and accrued rewards are correctly updated
        // User2 should not earn rewards after withdrawing everything

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser2AccruedRewards += Math.mulDiv(newRewards, expectedUser2TotalStaked, expectedTotalStaked);
        expectedUser3AccruedRewards += Math.mulDiv(newRewards, expectedUser3TotalStaked, expectedTotalStaked);
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        user2.withdraw(expectedUser2TotalStaked);
        expectedTotalStaked -= expectedUser2TotalStaked;
        expectedUser2TotalStaked = 0;

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // Some time passes and user2 claims the rewards, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser3AccruedRewards += newRewards;
        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );

        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user2));
        user2.claimRewards();
        totalDistributedRewards -= rewardToken.balanceOf(address(user2)) - rewardTokenBalanceBefore;

        _validateAccruedRewards(0, 0, expectedUser3AccruedRewards, totalDistributedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user2)), rewardTokenBalanceBefore + expectedUser2AccruedRewards, ABS_TOLERANCE
        );
        expectedUser2AccruedRewards = 0;

        // Some time passes and user3 withdraws all the tokens, check that his position and accrued rewards are correctly updated

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        newRewards = timeToPass * emissionPerSecond;
        totalDistributedRewards += newRewards;
        expectedUser3AccruedRewards += newRewards;
        _validateAccruedRewards(0, 0, expectedUser3AccruedRewards, totalDistributedRewards);

        user3.withdraw(expectedUser3TotalStaked);
        expectedTotalStaked = 0;
        expectedUser3TotalStaked = 0;

        _validateAccruedRewards(0, 0, expectedUser3AccruedRewards, totalDistributedRewards);
        _validateUsersStakedAmounts(expectedUser1TotalStaked, expectedUser2TotalStaked, expectedUser3TotalStaked);

        // Some time passes and no rewards are accrued by any user
        // User3 claims rewards that he accrued before withdrawing

        timeToPass = 123;
        vm.warp(block.timestamp + timeToPass);
        totalDistributedRewards += timeToPass * emissionPerSecond;

        _validateAccruedRewards(
            expectedUser1AccruedRewards,
            expectedUser2AccruedRewards,
            expectedUser3AccruedRewards,
            totalDistributedRewards
        );
        rewardTokenBalanceBefore = rewardToken.balanceOf(address(user3));
        user3.claimRewards();

        _validateAccruedRewards(0, 0, 0, 0);
        _validateUsersStakedAmounts(0, 0, 0);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(user3)), rewardTokenBalanceBefore + expectedUser3AccruedRewards, ABS_TOLERANCE
        );

        // Some time passes and no rewards are accrued by any user and no one has position

        timeToPass = 1_000_000_000_000_000;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 0, 0, 0);
        _validateUsersStakedAmounts(0, 0, 0);
    }

    /*
      This scenario is complex scenario where multiple users are staking and unstaking tokens and claiming rewards.
      All values in this test are hardocded. All rewards are manually calculated and should not be changed. This test is
      used to prove that smart contract distributes rewards correctly and that all values are correctly updated after
      each action. This test is used to prove that we did not copy formulas from smart contract to tests directly or indirectly.
      Scenario is similar to previous one.
    */
    function testClaimRewards_MultipleStakers_PredefinedValues() public {
        // Configure the reward token

        staking.configureRewardToken(
            address(token),
            address(rewardToken),
            RewardTokenConfig({
                startTimestamp: block.timestamp,
                endTimestamp: type(uint256).max,
                emissionPerSecond: 1 ether
            })
        );

        // User1 deposits 10 tokens, check that his position and accrued rewards are correctly updated, rewards should be 0

        uint256 amount = 10 ether;
        user1.deposit(amount);

        _validateUsersStakedAmounts(10 ether, 0, 0);
        _validateAccruedRewards(0, 0, 0, 0);

        // After 100 seconds user2 deposits 20 tokens, check that his position and accrued rewards are correctly updated
        // User1 should have 100 tokens in rewards since he was only staker for 100 seconds

        uint256 timeToPass = 100;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(100 ether, 0, 0, 100 ether);

        amount = 20 ether;
        user2.deposit(amount);

        _validateUsersStakedAmounts(10 ether, 20 ether, 0);
        _validateAccruedRewards(100 ether, 0, 0, 100 ether);

        // After 30 seconds user3 deposits 30 tokens, check that his position and accrued rewards are correctly updated
        // After previous action 30 tokens are emitted as rewards, user1 should have 10 and user2 20 tokens in rewards
        // User1 should now have 110 tokens in total rewards

        timeToPass = 30;
        vm.warp(block.timestamp + timeToPass);

        amount = 30 ether;
        user3.deposit(amount);

        _validateUsersStakedAmounts(10 ether, 20 ether, 30 ether);
        _validateAccruedRewards(110 ether, 20 ether, 0, 130 ether);

        // After 60 seconds user1 claims the rewards, check that his position and accrued rewards are correctly updated
        // From previous action 60 tokens are emitted as rewards, user1 should have 10 and user2 20 tokens in rewards and user3 30 tokens
        // User1 should now have 120 tokens in total rewards
        // User2 should have 40 tokens in rewards
        // User3 should have 30 tokens in rewards

        timeToPass = 60;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(120 ether, 40 ether, 30 ether, 190 ether);

        user1.claimRewards();

        _validateAccruedRewards(0, 40 ether, 30 ether, 70 ether);
        _validateUsersStakedAmounts(10 ether, 20 ether, 30 ether);

        // After 90 seconds user3 withdraws all the tokens, check that his position and accrued rewards are correctly updated
        // From previous action 90 tokens are emitted as rewards, user1 should have 15, user2 30 and user3 45 tokens in rewards
        // User1 should now have 15 tokens in total rewards because he claimed previous rewards
        // User2 should have 70 tokens in rewards
        // User3 should have 75 tokens in rewards

        timeToPass = 90;
        vm.warp(block.timestamp + timeToPass);

        user3.withdraw(30 ether);

        _validateAccruedRewards(15 ether, 70 ether, 75 ether, 160 ether);
        _validateUsersStakedAmounts(10 ether, 20 ether, 0);

        // After 180 seconds user3 claims the rewards, check that his position and accrued rewards are correctly updated
        // From previous action 180 tokens are emitted as rewards, user1 should have 60 and user2 120
        // User1 should now have 75 tokens in total rewards
        // User2 should have 190 tokens in rewards
        // User3 should have 75 tokens in rewards because he withdrew everything and didn't earn anythign after that

        timeToPass = 180;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(75 ether, 190 ether, 75 ether, 340 ether);
        _validateUsersStakedAmounts(10 ether, 20 ether, 0);

        user3.claimRewards();

        _validateAccruedRewards(75 ether, 190 ether, 0, 265 ether);
        _validateUsersStakedAmounts(10 ether, 20 ether, 0);

        // 30 seconds passes and user3 stakes 10 tokens
        // From previous action 30 tokens are emitted as rewards, user1 should have 10 and user2 20
        // User1 should now have 85 tokens in total rewards
        // User2 should have 210 tokens in rewards
        // User3 should have 0 tokens in rewards because he claimed everything and withdrew everything

        timeToPass = 30;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(85 ether, 210 ether, 0, 295 ether);

        user3.deposit(10 ether);

        _validateAccruedRewards(85 ether, 210 ether, 0, 295 ether);
        _validateUsersStakedAmounts(10 ether, 20 ether, 10 ether);

        // 400 seconds passes and user2 claims the rewards, check that his position and accrued rewards are correctly updated
        // From previous action 400 tokens are emitted as rewards, user1 should have 100, user2 200 and user3 100
        // User1 should now have 185 tokens in total rewards
        // User2 should have 410 tokens in rewards
        // User3 should have 100 tokens in rewards

        timeToPass = 400;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(185 ether, 410 ether, 100 ether, 695 ether);

        user2.claimRewards();

        _validateAccruedRewards(185 ether, 0, 100 ether, 400 ether);
        _validateUsersStakedAmounts(10 ether, 20 ether, 10 ether);

        // 60 seconds passes and user1 withdraws all the tokens, check that his position and accrued rewards are correctly updated
        // From previous action 60 tokens are emitted as rewards, user1 should have 15, user2 30 and user3 15
        // User1 should now have 200 tokens in total rewards
        // User2 should have 30 tokens in rewards
        // User3 should have 115 tokens in rewards

        timeToPass = 60;
        vm.warp(block.timestamp + timeToPass);

        user1.withdraw(10 ether);

        _validateAccruedRewards(200 ether, 30 ether, 115 ether, 345 ether);
        _validateUsersStakedAmounts(0, 20 ether, 10 ether);

        // 90 seconds passes and user1 claims the rewards, check that his position and accrued rewards are correctly updated
        // From previous action 90 tokens are emitted as rewards user2 should have 60 and user3 30
        // User1 should now have 200 tokens in total rewards
        // User2 should have 90 tokens in rewards
        // User3 should have 145 tokens in rewards

        timeToPass = 90;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(200 ether, 90 ether, 145 ether, 435 ether);

        user1.claimRewards();

        _validateAccruedRewards(0, 90 ether, 145 ether, 235 ether);
        _validateUsersStakedAmounts(0, 20 ether, 10 ether);

        // 30 seconds passes and no rewards are accrued for user1, all new rewards are split between user2 and user3
        // User1 should now have 0 tokens in total rewards
        // User2 should have 110 tokens in rewards
        // User3 should have 155 tokens in rewards

        timeToPass = 30;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 110 ether, 155 ether, 265 ether);
        _validateUsersStakedAmounts(0, 20 ether, 10 ether);

        // 45 seconds passes and user2 claims the rewards, check that his position and accrued rewards are correctly updated
        // From previous action 45 tokens are emitted as rewards user2 should have 30 and user3 15
        // User1 should now have 0 tokens in total rewards
        // User2 should have 140 tokens in rewards
        // User3 should have 170 tokens in rewards

        timeToPass = 45;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 140 ether, 170 ether, 310 ether);

        user2.claimRewards();

        _validateAccruedRewards(0, 0, 170 ether, 170 ether);
        _validateUsersStakedAmounts(0, 20 ether, 10 ether);

        // 120 seconds passes and user2 withdraws all the tokens, check that his position and accrued rewards are correctly updated
        // From previous action 120 tokens are emitted as rewards user2 should have 80 and user3 40
        // User1 should now have 0 tokens in total rewards
        // User2 should have 80 tokens in rewards
        // User3 should have 210 tokens in rewards

        timeToPass = 120;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 80 ether, 210 ether, 290 ether);

        user2.withdraw(20 ether);

        _validateAccruedRewards(0, 80 ether, 210 ether, 290 ether);
        _validateUsersStakedAmounts(0, 0, 10 ether);

        // 10 seconds passes and user2 claims the rewards, check that his position and accrued rewards are correctly updated
        // From previous action 10 tokens are emitted and user3 should have all of them
        // User1 should now have 0 tokens in total rewards
        // User2 should have 80 tokens in rewards
        // User3 should have 220 tokens in rewards

        timeToPass = 10;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 80 ether, 220 ether, 300 ether);

        user2.claimRewards();

        _validateAccruedRewards(0, 0, 220 ether, 220 ether);
        _validateUsersStakedAmounts(0, 0, 10 ether);

        // 10 seconds passes and user3 withdraws all the tokens, check that his position and accrued rewards are correctly updated
        // From previous action 10 tokens are emitted and user3 should have all of them
        // User1 should now have 0 tokens in total rewards
        // User2 should have 0 tokens in rewards
        // User3 should have 230 tokens in rewards

        timeToPass = 10;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 0, 230 ether, 230 ether);

        user3.withdraw(10 ether);

        _validateAccruedRewards(0, 0, 230 ether, 230 ether);
        _validateUsersStakedAmounts(0, 0, 0);

        // Some time passes and no rewards are accrued by any user
        // User3 claims rewards that he accrued before withdrawing

        timeToPass = 123;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 0, 230 ether, 230 ether);

        user3.claimRewards();

        _validateAccruedRewards(0, 0, 0, 0);
        _validateUsersStakedAmounts(0, 0, 0);

        // Some time passes and no rewards are accrued by any user and no one has position

        timeToPass = 23452;
        vm.warp(block.timestamp + timeToPass);

        _validateAccruedRewards(0, 0, 0, 0);
        _validateUsersStakedAmounts(0, 0, 0);
    }

    function _validateAccruedRewards(
        uint256 expectedUser1AccruedRewards,
        uint256 expectedUser2AccruedRewards,
        uint256 expectedUser3AccruedRewards,
        uint256 totalDistributedRewards
    ) internal {
        uint256 user1Rewards = staking.getUserTotalRewardsForToken(address(user1), address(token), address(rewardToken));
        uint256 user2Rewards = staking.getUserTotalRewardsForToken(address(user2), address(token), address(rewardToken));
        uint256 user3Rewards = staking.getUserTotalRewardsForToken(address(user3), address(token), address(rewardToken));

        assertApproxEqAbs(user1Rewards, expectedUser1AccruedRewards, ABS_TOLERANCE);
        assertApproxEqAbs(user2Rewards, expectedUser2AccruedRewards, ABS_TOLERANCE);
        assertApproxEqAbs(user3Rewards, expectedUser3AccruedRewards, ABS_TOLERANCE);

        assertLe(user1Rewards + user2Rewards + user3Rewards, totalDistributedRewards);
    }

    function _validateUsersStakedAmounts(
        uint256 expectedUser1TotalStaked,
        uint256 expectedUser2TotalStaked,
        uint256 expectedUser3TotalStaked
    ) internal {
        assertEq(staking.getUserStakedBalance(address(user1), address(token)), expectedUser1TotalStaked);
        assertEq(staking.getUserStakedBalance(address(user2), address(token)), expectedUser2TotalStaked);
        assertEq(staking.getUserStakedBalance(address(user3), address(token)), expectedUser3TotalStaked);

        uint256 expectedTotalStaked = expectedUser1TotalStaked + expectedUser2TotalStaked + expectedUser3TotalStaked;
        assertEq(staking.getTotalStaked(address(token)), expectedTotalStaked);
        assertEq(token.balanceOf(address(staking)), expectedTotalStaked);
    }
}
