// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StakedToken} from "../../src/safety-module/StakedToken.sol"; // Adjust import paths to your project structure
import {IStakedToken} from "../../src/interfaces/IStakedToken.sol";
import {StakedTokenStorage} from "../../src/storage/StakedTokenStorage.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";
import {RewardKeeper} from "../../src/safety-module/RewardKeeper.sol";
import {MockPool} from "../mocks/MockPool.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockFactory} from "../mocks/MockFactory.sol";
import {StakedTokenTester} from "../mocks/StakedTokenTester.sol";

contract StakedTokenTest is Test {
    StakedToken internal stakedToken;
    StakedTokenTester internal testToken;
    ERC20Mock underlyingAsset;

    ERC20Mock internal mockToken1;
    ERC20Mock internal mockToken2;

    MockPool internal mockPool;
    MockOracle internal oracle;
    MockFactory internal factory;
    RewardsController internal rewardsController;
    RewardKeeper internal rewardKeeper;

    // Test addresses
    address internal admin = address(0xA11CE);
    address internal manager = address(0xBEEF);
    address internal pauser = address(0xDEAD);
    address internal user = address(0xCAFE);
    address internal treasury = address(0xEAAE);

    // Roles
    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Cooldown/Unstake config
    uint256 internal defaultCooldown = 3 days;
    uint256 internal defaultUnstakeWindow = 2 days;
    address a1;

    function setUp() public {
        mockToken1 = new ERC20Mock();
        mockToken2 = new ERC20Mock();
        mockToken1.mint(address(this), 1_000_000 ether);
        mockToken2.mint(address(this), 2_000_000 ether);

        underlyingAsset = new ERC20Mock();

        oracle = new MockOracle();

        // Deploy the StakedToken (UUPS proxy-like) directly for testing
        StakedToken implementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                implementation.initialize.selector,
                address(underlyingAsset),
                admin,
                "StakedToken",
                "STK",
                defaultCooldown,
                defaultUnstakeWindow
            )
        );
        stakedToken = StakedToken(address(proxy));

        address[] memory reserves = new address[](2);
        reserves[0] = address(mockToken1);
        reserves[1] = address(mockToken2);
        mockPool = new MockPool(reserves, treasury);

        a1 = mockPool.setReserveData(address(mockToken1), address(mockToken1));
        address a2 = mockPool.setReserveData(address(mockToken2), address(mockToken2));
        address[] memory aTokens = new address[](2);
        aTokens[0] = a1;
        aTokens[1] = a2;
        factory = new MockFactory();
        factory.createStaticATokens(reserves, aTokens);

        RewardKeeper implementation2 = new RewardKeeper();
        proxy = new ERC1967Proxy(
            address(implementation2),
            abi.encodeWithSelector(
                implementation2.initialize.selector,
                address(mockPool),
                admin,
                address(stakedToken),
                address(oracle),
                treasury,
                address(factory)
            )
        );
        rewardKeeper = RewardKeeper(address(proxy));

        rewardsController = new RewardsController(address(rewardKeeper));

        vm.startPrank(treasury);
        IERC20(a1).approve(address(rewardKeeper), 10000000000 ether);
        IERC20(a2).approve(address(rewardKeeper), 10000000000 ether);
        vm.stopPrank();

        // Grant roles to manager and pauser
        vm.startPrank(admin);
        rewardKeeper.setRewardsController(address(rewardsController));
        stakedToken.setController(address(rewardsController));
        stakedToken.grantRole(MANAGER_ROLE, manager);
        stakedToken.grantRole(PAUSER_ROLE, pauser);
        stakedToken.grantRole(UPGRADER_ROLE, admin); // So admin can upgrade in tests
        stakedToken.setController(address(rewardsController));
        vm.stopPrank();

        // Mint some tokens to user for testing
        underlyingAsset.mint(user, 10_000 ether);
        // Approve the StakedToken to spend user's tokens
        vm.prank(user);
        underlyingAsset.approve(address(stakedToken), type(uint256).max);

        vm.prank(address(rewardKeeper));
        IERC20(a1).approve(factory.getStaticAToken(address(mockToken1)), 1000000000 ether);
    }

    function _upgradeAndSetTestValues() internal {
        // 1) Upgrade from originalImplementation -> testImplementation
        StakedTokenTester testImp = new StakedTokenTester();
        vm.prank(admin);
        stakedToken.upgradeToAndCall(address(testImp), "");

        // 2) Now cast the proxy to our testable interface
        testToken = StakedTokenTester(address(stakedToken));
    }

    function testInitialization() public {
        // Basic check that initialization was correct
        assertEq(stakedToken.asset(), address(underlyingAsset), "Incorrect underlying asset");
        assertEq(
            address(stakedToken.getRewardsController()), address(rewardsController), "Incorrect rewards controller"
        );
        assertEq(stakedToken.getCooldown(), defaultCooldown, "Incorrect default cooldown");
        assertEq(stakedToken.getUnstakeWindow(), defaultUnstakeWindow, "Incorrect default unstake window");

        // Check roles
        assertTrue(stakedToken.hasRole(stakedToken.DEFAULT_ADMIN_ROLE(), admin), "Admin not set");
        assertTrue(stakedToken.hasRole(MANAGER_ROLE, manager), "Manager not set");
        assertTrue(stakedToken.hasRole(PAUSER_ROLE, pauser), "Pauser not set");
    }

    function testDepositAndWithdraw() public {
        // Deposit
        vm.warp(block.timestamp + 500 days);
        vm.prank(user);
        uint256 sharesMinted = stakedToken.deposit(1000 ether, user);
        assertEq(sharesMinted, 1000 ether, "Shares minted should match deposit amount");
        assertEq(stakedToken.balanceOf(user), 1000 ether, "User's Staked balance mismatch");

        // Without cooldown, withdrawal should revert
        vm.prank(user);
        vm.expectRevert(IStakedToken.CooldownNotInitiated.selector);
        stakedToken.withdraw(1000 ether, user, user);

        // Initiate cooldown
        vm.prank(user);
        stakedToken.cooldown();
        // Advance time forward to pass the cooldown + stay within unstake window
        vm.warp(block.timestamp + defaultCooldown - 1);

        // Still in cooldown, now we can’t withdraw because it reverts if the block time hasn’t fully passed
        vm.prank(user);
        console.log(block.timestamp);
        vm.expectRevert(IStakedToken.CooldownStillActive.selector);
        stakedToken.withdraw(1000 ether, user, user);

        // Advance into the unstake window
        vm.warp(block.timestamp + 2); // Now block.timestamp > cooldownEnd

        vm.prank(user);
        stakedToken.withdraw(1000 ether, user, user);
        assertEq(stakedToken.balanceOf(user), 0, "Withdraw didn't burn shares");
        assertEq(underlyingAsset.balanceOf(user), 10_000 ether, "User should get back underlying tokens");
    }

    function test_getNextCooldownTimestamp_ReturnsZero_WhenToCooldownIsZero() public {
        // toAddress has no cooldown => stakersCooldowns[toAddress] == 0
        address toAddress = address(1);
        // layout().stakersCooldowns[toAddress] = 0;

        uint256 fromCooldown = 100;
        uint256 amountToReceive = 50;
        uint256 toBalance = 10;

        uint256 result = stakedToken.getNextCooldownTimestamp(fromCooldown, amountToReceive, toAddress, toBalance);

        assertEq(result, 0, "Should return zero when toCooldownTimestamp == 0");
    }

    function test_getNextCooldownTimestamp_ReturnsZero_WhenToCooldownExpired() public {
        address toAddress = address(2);
        _upgradeAndSetTestValues();
        // set some non-zero toCooldownTimestamp
        testToken.setStakersCooldownForTest(toAddress, 100); // old timestamp
        testToken.setCooldownSecondsForTest(10);
        testToken.setUnstakeWindowForTest(5);

        // Move time forward so that minimalValidCooldownTimestamp > 100
        // minimalValidCooldownTimestamp = block.timestamp - 10 - 5
        // We want that to be > 100 => block.timestamp = something greater than 115
        vm.warp(200);

        uint256 fromCooldown = 120;
        uint256 amountToReceive = 50;
        uint256 toBalance = 10;

        uint256 result = stakedToken.getNextCooldownTimestamp(fromCooldown, amountToReceive, toAddress, toBalance);

        // Because 100 < (200 - 10 - 5) => toCooldownTimestamp = 0
        assertEq(result, 0, "Should return zero when toCooldownTimestamp is expired");
    }

    function test_getNextCooldownTimestamp_ReturnsToCooldownTimestamp_WhenFromFinalLessThanTo() public {
        address toAddress = address(3);
        _upgradeAndSetTestValues();
        // We want toCooldownTimestamp still valid, let's pick a stable block.timestamp
        vm.warp(1000);
        testToken.setStakersCooldownForTest(toAddress, 990); // Not expired => must be > (1000 - 10 - 5) = 985
        testToken.setCooldownSecondsForTest(10);
        testToken.setUnstakeWindowForTest(5);

        // minimalValidCooldownTimestamp = 985
        // fromCooldownTimestamp = 900 => that is < 985 => fromCooldownTimestampFinal = block.timestamp (1000)
        // Then fromCooldownTimestampFinal = 1000
        // Compare 1000 < toCooldownTimestamp(??) -> not less, so let's adjust

        // Wait, we want fromCooldownTimestampFinal < 990. But fromCooldownTimestampFinal
        // will become 1000 if 900 < 985. So let's make fromCooldownTimestamp = 987 so it *won't* become 1000
        // Because 987 > 985 => fromCooldownTimestampFinal = 987 (not the block.timestamp).
        // So finalFromCooldown = 987.
        // Now finalFromCooldown(987) < toCooldownTimestamp(990) => we just return 990.

        uint256 fromCooldown = 987; // > 985 => use fromCooldown directly
        uint256 amountToReceive = 50;
        uint256 toBalance = 100;

        uint256 result = stakedToken.getNextCooldownTimestamp(fromCooldown, amountToReceive, toAddress, toBalance);

        // We expect it to just return existing toCooldownTimestamp of 990
        assertEq(result, 990, "Should return toCooldownTimestamp if fromCooldownTimestampFinal < toCooldown");
    }

    function test_getNextCooldownTimestamp_WeightedAverage() public {
        address toAddress = address(4);
        _upgradeAndSetTestValues();
        // We'll set block.timestamp to 1000 again for stable reference
        vm.warp(1000);

        // Keep toCooldownTimestamp valid (say 990)
        testToken.setStakersCooldownForTest(toAddress, 990);
        testToken.setCooldownSecondsForTest(10);
        testToken.setUnstakeWindowForTest(5);
        // minimalValidCooldownTimestamp = 985

        // We'll pick fromCooldown=987 => fromCooldownTimestampFinal=987
        // Then if finalFromCooldown(987) >= toCooldownTimestamp(990)? => actually 987 < 990,
        // that wouldn't trigger the weighted average. We need it >= 990.
        // So let's make fromCooldown=995 => fromCooldownTimestampFinal=995.

        uint256 fromCooldown = 995;
        uint256 amountToReceive = 50;
        uint256 toBalance = 100;

        // fromCooldownTimestampFinal=995 >= toCooldownTimestamp(990),
        // Weighted average => newTimestamp = (50*995 + 100*990) / (50 + 100)
        // = (49750 + 99000) / 150
        // = 148750 / 150
        // = 991.666..., trunc in solidity => 991

        uint256 result = stakedToken.getNextCooldownTimestamp(fromCooldown, amountToReceive, toAddress, toBalance);
        assertEq(result, 991, "Should return weighted average for fromCooldownTimestampFinal >= toCooldownTimestamp");
    }

    function test_getNextCooldownTimestamp_WeightedAverage_FromExpired() public {
        address toAddress = address(5);
        _upgradeAndSetTestValues();

        // Set block.timestamp
        vm.warp(1000);
        testToken.setStakersCooldownForTest(toAddress, 990);
        testToken.setCooldownSecondsForTest(10);
        testToken.setUnstakeWindowForTest(5);
        // minimalValidCooldownTimestamp = 985

        uint256 cd = stakedToken.getStakerCooldown(toAddress);
        assertEq(cd, 990);

        // fromCooldown=900 => it's < 985 => fromCooldownTimestampFinal = block.timestamp(1000)
        // Then 1000 >= 990 => Weighted average => (amountToReceive*1000 + toBalance*990) / (sum)
        // Let amountToReceive=10, toBalance=5 => (10*1000 + 5*990) / (15) => (10000 + 4950) / 15 = 14950 / 15 = 996
        // Actually 996.666..., integer trunc => 996
        uint256 fromCooldown = 900;
        uint256 amountToReceive = 10;
        uint256 toBalance = 5;

        uint256 result = stakedToken.getNextCooldownTimestamp(fromCooldown, amountToReceive, toAddress, toBalance);
        assertEq(result, 996, "Should return integer-truncated weighted average using block.timestamp");
    }

    function testTransferCooldownLogicSimple() public {
        // user deposits
        vm.prank(user);
        stakedToken.deposit(1000 ether, user);

        // user starts cooldown
        vm.prank(user);
        stakedToken.cooldown();

        assertEq(stakedToken.getStakerCooldown(user), block.timestamp, "Sender's cooldown is not set");

        // If user transfers all shares to a fresh address, user cooldown is reset to 0
        address recipient = address(0xBABE);

        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                rewardsController.handleAction.selector, user, stakedToken.totalSupply(), stakedToken.balanceOf(user)
            )
        );
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                rewardsController.handleAction.selector,
                recipient,
                stakedToken.totalSupply(),
                stakedToken.balanceOf(recipient)
            )
        );

        vm.prank(user);
        stakedToken.transfer(recipient, 1000 ether);

        // user cooldown should be reset to 0
        assertEq(stakedToken.getStakerCooldown(user), 0, "Sender's cooldown not cleared after transfer");
        // recipient's cooldown should stay zero
        assertEq(stakedToken.getStakerCooldown(recipient), 0, "Recipient's cooldown not set");
    }

    function testTransferCooldownLogicTimestampsChange() public {
        vm.warp(block.timestamp + 500 days);
        address recipient = address(0xBABE);
        vm.prank(user);

        underlyingAsset.transfer(recipient, 300 ether);
        // user deposits
        vm.prank(user);
        stakedToken.deposit(700 ether, user);

        // user starts cooldown
        vm.prank(user);
        stakedToken.cooldown();

        assertEq(stakedToken.getStakerCooldown(user), block.timestamp, "Sender's cooldown is not set");

        vm.warp(block.timestamp + 12 hours);

        vm.startPrank(recipient);
        underlyingAsset.approve(address(stakedToken), 300 ether);
        stakedToken.deposit(300 ether, recipient);
        stakedToken.cooldown();
        vm.stopPrank();

        vm.warp(block.timestamp + 16 hours);

        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                rewardsController.handleAction.selector, user, stakedToken.totalSupply(), stakedToken.balanceOf(user)
            )
        );
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                rewardsController.handleAction.selector,
                recipient,
                stakedToken.totalSupply(),
                stakedToken.balanceOf(recipient)
            )
        );

        vm.prank(user);
        stakedToken.transfer(recipient, 700 ether);

        // user cooldown should be reset to 0
        assertEq(stakedToken.getStakerCooldown(user), 0, "Sender's cooldown not cleared after transfer");
        // recipient's cooldown should be > 0
        assertTrue(stakedToken.getStakerCooldown(recipient) > 0, "Recipient's cooldown not set");
    }

    function testPauseAndEmergencyWithdraw() public {
        // deposit some tokens
        vm.prank(user);
        stakedToken.deposit(1000 ether, user);

        vm.prank(manager);
        stakedToken.emergencyWithdrawal(user, 1 ether);

        // Only pauser can enable emergency
        vm.prank(user);
        vm.expectRevert(); // user does not have PAUSER_ROLE
        stakedToken.pause();

        // Pauser triggers emergency
        vm.prank(pauser);
        stakedToken.pause();

        // Contract is paused, normal deposits/withdraws revert
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        stakedToken.deposit(1 ether, user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        stakedToken.withdraw(1 ether, user, user);

        // manager can do emergencyWithdrawal
        uint256 balBefore = underlyingAsset.balanceOf(user);
        vm.prank(manager);
        stakedToken.emergencyWithdrawal(user, 500 ether);

        // Check user received underlying

        assertEq(
            balBefore + 500 ether, underlyingAsset.balanceOf(user), "user not receiving correct emergency withdrawal"
        );

        // End emergency state
        vm.prank(pauser);
        stakedToken.unpause();

        // normal deposit again
        uint256 toAdd = stakedToken.previewDeposit(1 ether);
        vm.prank(user);
        stakedToken.deposit(1 ether, user);
        assertEq(stakedToken.balanceOf(user), 1000 ether + toAdd, "Deposit after emergency ended failed");
    }

    function testChangeRewardsController() public {
        address newController = address(0x9999);

        // Only manager can change
        vm.prank(user);
        vm.expectRevert(); // user is not manager
        stakedToken.setController(newController);

        // Manager can set
        vm.prank(manager);
        stakedToken.setController(newController);
        assertEq(address(stakedToken.getRewardsController()), newController, "Controller not updated");

        // Zero address revert
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.ZeroAddress.selector));
        stakedToken.setController(address(0));
    }

    function testChangeTimers() public {
        uint256 newCooldown = 10 days;
        uint256 newUnstakeWindow = 3 days;

        // Non-manager attempt
        vm.prank(user);
        vm.expectRevert(); // user not manager
        stakedToken.setTimers(newCooldown, newUnstakeWindow);

        vm.prank(manager);
        stakedToken.setTimers(newCooldown, newUnstakeWindow);
        assertEq(stakedToken.getCooldown(), newCooldown, "Cooldown not updated");
        assertEq(stakedToken.getUnstakeWindow(), newUnstakeWindow, "Unstake window not updated");
    }

    function testUpgradeRequiresUpgraderRole() public {
        StakedToken upgrade = new StakedToken();
        vm.expectRevert();
        stakedToken.upgradeToAndCall(address(upgrade), "");

        vm.prank(admin);
        stakedToken.upgradeToAndCall(address(upgrade), "");
    }

    function testCooldownAtZeroBal() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.InsufficientStake.selector));
        stakedToken.cooldown();
    }

    function testCantWithdrawAfterUnstakeWindow() public {
        vm.warp(block.timestamp + 5 days);

        vm.prank(user);
        stakedToken.deposit(1000 ether, user);

        vm.prank(user);
        stakedToken.cooldown();

        vm.warp(block.timestamp + 20 days);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.UnstakeWindowExpired.selector));
        stakedToken.withdraw(1000 ether, user, user);
    }

    function testNonces() public {
        vm.prank(user);
        uint256 n = stakedToken.nonces(user);
        assertEq(n, 0);
    }

    function testHandleAction() public {
        vm.warp(block.timestamp + 5 days);

        rewardKeeper.claimAndSetRate();
        address sa1 = factory.getStaticAToken(address(mockToken1));
        address sa2 = factory.getStaticAToken(address(mockToken2));

        address[] memory assets = new address[](1);
        assets[0] = address(stakedToken);
        uint256 indexBefore = rewardsController.getUserRewards(assets, user, sa1);
        assertEq(indexBefore, 0);

        vm.prank(user);
        stakedToken.deposit(1000 ether, user);

        vm.warp(block.timestamp + 10);
        uint256 indexAfter = rewardsController.getUserRewards(assets, user, sa1);
        assertTrue(indexAfter > 0);
    }

    function testHandleActionWhenFromIsNotZero() public {
        vm.warp(block.timestamp + 5 days);
        address user2 = address(2);

        rewardKeeper.claimAndSetRate();
        address sa1 = factory.getStaticAToken(address(mockToken1));
        address sa2 = factory.getStaticAToken(address(mockToken2));

        address[] memory assets = new address[](1);
        assets[0] = address(stakedToken);
        uint256 indexBefore = rewardsController.getUserRewards(assets, user, sa1);
        uint256 indexBefore2 = rewardsController.getUserRewards(assets, user2, sa2);
        assertEq(indexBefore, 0);
        assertEq(indexBefore2, 0);

        vm.prank(user);
        stakedToken.deposit(1000 ether, user);

        vm.prank(user);
        stakedToken.transfer(user2, 500 ether);

        vm.warp(block.timestamp + 10);
        uint256 indexAfter = rewardsController.getUserRewards(assets, user, sa1);
        assertTrue(indexAfter > 0);

        uint256 indexAfter2 = rewardsController.getUserRewards(assets, user2, sa2);
        assertTrue(indexAfter2 > 0);
    }

    function testHandleActionWhenFromIsNotZeroAndActiveCooldown() public {
        vm.warp(block.timestamp + 5 days);
        address user2 = address(2);

        rewardKeeper.claimAndSetRate();

        address[] memory assets = new address[](1);
        assets[0] = address(stakedToken);

        vm.prank(user);
        stakedToken.deposit(1000 ether, user);

        vm.prank(user);
        stakedToken.cooldown();
        vm.warp(block.timestamp + 10);

        uint256 indexBefore = rewardsController.getUserRewards(assets, user, address(mockToken1));
        uint256 indexBefore2 = rewardsController.getUserRewards(assets, user2, address(mockToken1));
        assertEq(indexBefore2, 0);
        vm.prank(user);
        stakedToken.transfer(user2, 1000 ether);

        uint256 indexAfter = rewardsController.getUserRewards(assets, user, address(mockToken1));
        assertEq(indexAfter, indexBefore);

        uint256 indexAfter2 = rewardsController.getUserRewards(assets, user2, address(mockToken1));
        assertTrue(indexAfter2 == 0);
    }

    function testClaimManyUsersAndWithdraw() public {
        uint256 userCount = 2;
        vm.warp(block.timestamp + 5 days);
        rewardKeeper.claimAndSetRate();
        IERC20 token1 = IERC20(factory.getStaticAToken(address(mockToken1)));

        address[] memory assets = new address[](1);
        assets[0] = address(stakedToken);

        for (uint256 k = 1; k <= userCount; k++) {
            address player = address(uint160(k));
            uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
            random = ((random % 5000) + 1) * 1e18;
            deal(address(underlyingAsset), player, random);
            vm.startPrank(player);
            underlyingAsset.approve(address(stakedToken), random);
            stakedToken.deposit(random, player);
            vm.stopPrank();
            vm.warp(block.timestamp + 3);
        }

        vm.warp(block.timestamp + 2 hours);
        (, uint256 rate,, uint256 endTime) = rewardsController.getRewardsData(address(stakedToken), address(token1));
        uint256 expectedPeriod = rewardKeeper.getPreviousPeriod();
        assertEq(1000 ether / expectedPeriod, rate, "wrong rate 0");
        uint256 leftOver = 1000 ether - (rate * expectedPeriod);
        uint256 transferBal0 = token1.balanceOf(rewardsController.getTransferStrategy(address(token1)));
        assertEq(token1.balanceOf(address(rewardKeeper)), leftOver, "Wrong leftover 0");
        assertEq(transferBal0, rate * expectedPeriod, "wrong bal 0");

        vm.warp(block.timestamp + 26 hours);
        rewardKeeper.claimAndSetRate();

        (, rate,, endTime) = rewardsController.getRewardsData(address(stakedToken), address(token1));
        expectedPeriod = rewardKeeper.getPreviousPeriod();
        assertEq((1000 ether + leftOver) / expectedPeriod, rate, "wrong rate 1");
        leftOver = (1000 ether + leftOver) - (rate * expectedPeriod);

        assertEq(token1.balanceOf(address(rewardKeeper)), leftOver, "Wrong leftover 1");
        assertEq(
            token1.balanceOf(rewardsController.getTransferStrategy(address(token1))),
            rate * expectedPeriod + transferBal0,
            "wrong bal 1"
        );

        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            vm.startPrank(player);
            console.log(player, 1);
            (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0);
            }
            vm.stopPrank();
        }
        transferBal0 = token1.balanceOf(rewardsController.getTransferStrategy(address(token1)));
        vm.warp(block.timestamp + 26 hours);
        rewardKeeper.claimAndSetRate();
        vm.warp(block.timestamp + 26 hours);

        (, rate,, endTime) = rewardsController.getRewardsData(address(stakedToken), address(token1));
        expectedPeriod = rewardKeeper.getPreviousPeriod();
        uint256 oldLeftover = leftOver;
        assertEq((1000 ether + leftOver) / expectedPeriod, rate, "wrong rate 2");
        leftOver = (1000 ether + leftOver) - (rate * expectedPeriod);

        assertEq(token1.balanceOf(address(rewardKeeper)), leftOver, "Wrong leftover 2");
        assertEq(
            token1.balanceOf(rewardsController.getTransferStrategy(address(token1))),
            rate * expectedPeriod + transferBal0,
            "wrong bal 2"
        );

        uint256 rewards1 = rewardsController.getUserRewards(assets, address(uint160(1)), address(token1));
        uint256 rewards2 = rewardsController.getUserRewards(assets, address(uint160(2)), address(token1));
        assertTrue(
            token1.balanceOf(rewardsController.getTransferStrategy(address(token1))) >= rewards1 + rewards2,
            "wrong total rewards"
        );

        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            vm.startPrank(player);
            console.log(player, 2);
            (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0, "Claim Amount Not greater than zero");
            }
            vm.warp(block.timestamp + 30);
            console.log(player, 3);
            (, claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] == 0, "Claim Amount not zero");
            }

            vm.stopPrank();
        }

        (, rate,, endTime) = rewardsController.getRewardsData(address(stakedToken), address(token1));
        expectedPeriod = rewardKeeper.getPreviousPeriod();
        assertEq((1000 ether + oldLeftover) / expectedPeriod, rate, "wrong rate 3");
        leftOver = (1000 ether + oldLeftover) - (rate * expectedPeriod);

        assertEq(token1.balanceOf(address(rewardKeeper)), leftOver, "Wrong leftover 3");
        assertTrue(token1.balanceOf(rewardsController.getTransferStrategy(address(token1))) < 10, "wrong bal 3");

        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            rewardKeeper.claimAndSetRate();
            vm.startPrank(player);
            stakedToken.cooldown();

            vm.warp(block.timestamp + 3 days + 2);
            console.log(player, 4);
            stakedToken.redeem(stakedToken.balanceOf(player), player, player);
            (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0);
            }
            vm.warp(block.timestamp + 2 hours);
            console.log(player, 5);
            (, claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] == 0);
            }
        }
    }
}
