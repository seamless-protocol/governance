// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StakedToken} from "../../src/safety-module/StakedToken.sol";
import {RewardKeeper} from "../../src/safety-module/RewardKeeper.sol"; // Adjust import paths to your project structure
import {IRewardKeeper} from "../../src/interfaces/IRewardKeeper.sol";
import {RewardKeeperStorage as StorageLib} from "../../src/storage/RewardKeeperStorage.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";

import {MockPool} from "../mocks/MockPool.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockFactory} from "../mocks/MockFactory.sol";

contract RewardKeeperTest is Test {
    RewardKeeper internal rewardKeeper;

    ERC20Mock internal SEAM;
    StakedToken internal stkSEAM;

    // Mocks
    MockPool internal mockPool;
    RewardsController internal rewardsController;
    ERC20Mock internal mockToken1;
    ERC20Mock internal mockToken2;
    MockOracle internal oracle;
    MockFactory internal factory;

    // Addresses
    address internal admin = address(0xA11CE);
    address internal upgradeAdmin = address(0xBABE);
    address internal treasury = address(0xEAAE);

    // Roles (same as in the contract, for convenience)
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function setUp() public {
        // Deploy mock tokens
        mockToken1 = new ERC20Mock();
        mockToken2 = new ERC20Mock();
        SEAM = new ERC20Mock();

        mockToken1.mint(address(this), 1_000_000 ether);
        mockToken2.mint(address(this), 2_000_000 ether);
        SEAM.mint(address(this), 1_000_000 ether);

        oracle = new MockOracle();

        // deploy stkSEAM
        StakedToken Imp = new StakedToken();
        ERC1967Proxy prox = new ERC1967Proxy(
            address(Imp),
            abi.encodeWithSelector(
                Imp.initialize.selector, address(SEAM), admin, "Staked Seam", "stkSEAM", 7 days, 1 days
            )
        );
        stkSEAM = StakedToken(address(prox));

        // Deploy mockPool with two reserve tokens
        address[] memory reserves = new address[](2);
        reserves[0] = address(mockToken1);
        reserves[1] = address(mockToken2);
        mockPool = new MockPool(reserves, treasury);

        address a1 = mockPool.setReserveData(address(mockToken1), address(mockToken1));
        address a2 = mockPool.setReserveData(address(mockToken2), address(mockToken2));
        address[] memory aTokens = new address[](2);
        aTokens[0] = a1;
        aTokens[1] = a2;
        factory = new MockFactory();
        factory.createStaticATokens(reserves, aTokens);

        RewardKeeper implementation = new RewardKeeper();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                implementation.initialize.selector,
                address(mockPool),
                admin,
                address(stkSEAM),
                address(oracle),
                treasury,
                address(factory)
            )
        );
        rewardKeeper = RewardKeeper(address(proxy));

        vm.startPrank(treasury);
        IERC20(a1).approve(address(rewardKeeper), 10000000000 ether);
        IERC20(a2).approve(address(rewardKeeper), 10000000000 ether);
        vm.stopPrank();

        rewardsController = new RewardsController(address(rewardKeeper));

        vm.prank(admin);
        rewardKeeper.setRewardsController(address(rewardsController));

        vm.prank(admin);
        stkSEAM.setController(address(rewardsController));

        // Give admin the UPGRADER_ROLE for testing upgrades
        SEAM.mint(admin, 1_000_000 ether);

        vm.startPrank(admin);

        rewardKeeper.grantRole(UPGRADER_ROLE, upgradeAdmin);

        SEAM.approve(address(stkSEAM), 1_000_000_000 ether);

        stkSEAM.deposit(1000 ether, admin);

        vm.stopPrank();
    }

    function testInitializeSetsValues() public {
        // Check storage layout values
        IRewardsController _controller = rewardKeeper.getController();
        IPool _pool = rewardKeeper.getPool();
        IEACAggregatorProxy _oracle = rewardKeeper.getOracle();
        address _asset = rewardKeeper.getAsset();
        uint256 _period = rewardKeeper.getPeriod();
        uint256 _previousPeriod = rewardKeeper.getPreviousPeriod();
        uint256 _lastClaim = rewardKeeper.getLastClaim();

        assertEq(address(_controller), address(rewardsController), "manager mismatch");
        assertEq(address(_pool), address(mockPool), "pool mismatch");
        assertEq(address(_oracle), address(oracle), "controller mismatch");
        assertEq(_previousPeriod, 0);
        assertEq(_period, 1 days, "wrong period");
        assertEq(_lastClaim, block.timestamp, "Wrong last claim");
        assertEq(_asset, address(stkSEAM), "asset mismatch");
    }

    function testOnlyManagerCanSetPool() public {
        vm.expectRevert(); // revert due to missing MANAGER_ROLE
        rewardKeeper.setPool(address(0xABC));

        vm.prank(admin);
        rewardKeeper.setPool(address(0xABC));

        IPool pool = rewardKeeper.getPool();
        assertEq(address(pool), address(0xABC), "Pool not updated");
    }

    function testOnlyManagerCanSetPeriod() public {
        vm.expectRevert();
        rewardKeeper.setPeriod(2 days);

        vm.prank(admin);
        rewardKeeper.setPeriod(2 days);

        uint256 _period = rewardKeeper.getPeriod();
        assertEq(_period, 2 days, "Period not updated");
    }

    function testPauseAndUnpause() public {
        // Admin needs PAUSER_ROLE to pause
        vm.expectRevert();
        rewardKeeper.pause();

        // Grant the PAUSER_ROLE to admin
        vm.prank(admin);
        rewardKeeper.grantRole(PAUSER_ROLE, admin);

        // Now admin can pause
        vm.prank(admin);
        rewardKeeper.pause();
        assertTrue(rewardKeeper.paused(), "Contract should be paused");

        // And unpause
        vm.prank(admin);
        rewardKeeper.unpause();
        assertFalse(rewardKeeper.paused(), "Contract should be unpaused");
    }

    function testSetPeriodRevertsWhenZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.InvalidPeriod.selector));
        rewardKeeper.setPeriod(0);
    }

    function testSetRewardsControllerRevertsWhenZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.ZeroAddress.selector, address(0)));
        rewardKeeper.setRewardsController(address(0));
    }

    function testSetPoolRevertsWhenZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.ZeroAddress.selector, address(0)));
        rewardKeeper.setPool(address(0));
    }

    function testClaimAndSetRateRevertsIfNotEnoughTimePassed() public {
        // will never have block.timestamp = 1. This would cause math issues. So warp to the future.
        vm.warp(block.timestamp + 5000 days);

        rewardKeeper.claimAndSetRate();
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.InsufficientTimeElapsed.selector));
        rewardKeeper.claimAndSetRate();
    }

    function testClaimAndSetRateSucceedsIfPeriodElapsed() public {
        vm.warp(block.timestamp + 1 days + 1);

        rewardKeeper.claimAndSetRate();

        // Check that lastClaim updated
        uint256 lastClaim = rewardKeeper.getLastClaim();
        uint256 previousPeriod = rewardKeeper.getPreviousPeriod();
        assertEq(lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(previousPeriod, 1 days - 2, "previousPeriod mismatch after claim");

        vm.warp(block.timestamp + 1 days + 30);
        uint256 nextMidnight = ((block.timestamp / 1 days) + 1) * 1 days;
        uint256 nextPeriod = nextMidnight - block.timestamp;
        rewardKeeper.claimAndSetRate();
        lastClaim = rewardKeeper.getLastClaim();
        previousPeriod = rewardKeeper.getPreviousPeriod();
        assertEq(lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(previousPeriod, nextPeriod, "previousPeriod mismatch after claim 2");
    }

    function testClaimAndSetRate_ExtremelyLateKeeper() public {
        vm.warp(block.timestamp + 5000 days);

        rewardKeeper.claimAndSetRate();

        //   - Move time forward by 2 days + some hours, e.g. 2.5 days
        vm.warp(block.timestamp + 2 * 86400 + 3600 * 12);

        // Act
        rewardKeeper.claimAndSetRate();
        uint256 lastClaim = rewardKeeper.getLastClaim();
        uint256 previousPeriod = rewardKeeper.getPreviousPeriod();
        assertEq(lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(previousPeriod, 12 hours - 1, "previousPeriod mismatch after claim");
    }

    function testClaimAndSetRateWithChangingPeriods() public {
        vm.warp(block.timestamp + 1 days + 1);

        rewardKeeper.claimAndSetRate();

        // Check that lastClaim updated
        uint256 lastClaim = rewardKeeper.getLastClaim();
        uint256 previousPeriod = rewardKeeper.getPreviousPeriod();
        assertEq(lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(previousPeriod, 1 days - 2, "previousPeriod mismatch after claim");

        vm.prank(admin);
        rewardKeeper.setPeriod(3 days);
        uint256 period = rewardKeeper.getPeriod();
        previousPeriod = rewardKeeper.getPreviousPeriod();
        assertEq(period, 3 days, "period incorrect");
        assertEq(previousPeriod, 1 days - 2, "previousPeriod should not change");

        vm.warp(block.timestamp + 23 hours);
        console.log(block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.InsufficientTimeElapsed.selector));
        rewardKeeper.claimAndSetRate();

        vm.warp(block.timestamp + 1 hours);
        uint256 nextMidnight = ((block.timestamp / 3 days) + 1) * 3 days;
        uint256 nextPeriod = nextMidnight - block.timestamp;
        rewardKeeper.claimAndSetRate();
        period = rewardKeeper.getPeriod();
        previousPeriod = rewardKeeper.getPreviousPeriod();

        assertEq(period, 3 days, "period incorrect");
        assertEq(previousPeriod, nextPeriod, "previousPeriod should not change");

        vm.warp(block.timestamp + (nextPeriod - 1));
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.InsufficientTimeElapsed.selector));
        rewardKeeper.claimAndSetRate();

        vm.warp(block.timestamp + 1 days);
        rewardKeeper.claimAndSetRate();
    }

    function testClaimAndSetRateCreatesNewTransferStrategyIfNoneFound() public {
        // Wait 1 day
        vm.warp(block.timestamp + 1 days + 1);

        address sa1 = factory.getStaticAToken(address(mockToken1));
        address sa2 = factory.getStaticAToken(address(mockToken2));

        // Initially, no strategy for mockToken1 or mockToken2
        assertEq(rewardsController.getTransferStrategy(sa1), address(0), "Should be no strategy");
        assertEq(rewardsController.getTransferStrategy(sa2), address(0), "Should be no strategy");

        // call claimAndSetRate
        vm.prank(address(this));
        rewardKeeper.claimAndSetRate();

        // Now, each should have a newly created ERC20TransferStrategy
        address strategy1 = rewardsController.getTransferStrategy(sa1);
        address strategy2 = rewardsController.getTransferStrategy(sa2);

        assertTrue(strategy1 != address(0), "Strategy1 not set");
        assertTrue(strategy2 != address(0), "Strategy2 not set");
    }

    function testUpgradeRequiresUpgraderRole() public {
        RewardKeeper upgrade = new RewardKeeper();
        vm.expectRevert();
        rewardKeeper.upgradeToAndCall(address(upgrade), "");

        vm.prank(upgradeAdmin);
        rewardKeeper.upgradeToAndCall(address(upgrade), "");
    }

    function testEmergencyWithdrawal() public {
        vm.warp(block.timestamp + 50 days);

        vm.startPrank(address(this));
        rewardKeeper.claimAndSetRate();

        address sa1 = factory.getStaticAToken(address(mockToken1));
        address sa2 = factory.getStaticAToken(address(mockToken2));

        address strategy1 = rewardsController.getTransferStrategy(sa1);
        address strategy2 = rewardsController.getTransferStrategy(sa2);

        vm.stopPrank();

        vm.prank(address(5555));
        vm.expectRevert();
        rewardKeeper.emergencyWithdrawalFromTransferStrategy(address(mockToken1), address(5555), 500_000 ether);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.TransferStrategyNotSet.selector));
        rewardKeeper.emergencyWithdrawalFromTransferStrategy(address(11), admin, 500_000 ether);

        vm.expectRevert(); // insufficient funds
        rewardKeeper.emergencyWithdrawalFromTransferStrategy(sa1, address(admin), 500_001_000 ether);

        uint256 balBefore = IERC20(sa1).balanceOf(admin);
        rewardKeeper.emergencyWithdrawalFromTransferStrategy(sa1, address(admin), 1 ether);
        uint256 balAfter = IERC20(sa1).balanceOf(admin);

        assertEq(balAfter, balBefore + 1 ether, "Withdrawal failed");
    }

    function testWithdrawTokens() public {
        mockToken1.transfer(address(rewardKeeper), 100);
        vm.expectRevert();
        rewardKeeper.withdrawTokens(address(mockToken1), address(this), 100);

        vm.prank(admin);
        rewardKeeper.withdrawTokens(address(mockToken1), admin, 100);

        uint256 balAdmin = mockToken1.balanceOf(admin);
        assertEq(balAdmin, 100, "Wrong balance");
    }
}
