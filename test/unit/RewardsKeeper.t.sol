// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RewardKeeper} from "../../src/safetyModule/rewardsKeeper.sol"; // Adjust import paths to your project structure
import {RewardKeeperStorage as StorageLib} from "../../src/storage/RewardKeeperStorage.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IEmissionManager} from "@aave/periphery-v3/contracts/rewards/interfaces/IEmissionManager.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MockRewardsController} from "../mocks/MockRewardsController.sol";
import {MockEmissionManager} from "../mocks/MockEmissionManager.sol";
import {MockPool} from "../mocks/MockPool.sol";






contract RewardKeeperTest is Test {
    RewardKeeper internal rewardKeeper;

    // Mocks
    MockPool internal mockPool;
    MockEmissionManager internal mockEmissionManager;
    MockRewardsController internal mockRewardsController;
    ERC20Mock internal mockToken1;
    ERC20Mock internal mockToken2;

    // Addresses
    address internal admin = address(0xA11CE);
    address internal treasury = address(0xFEEFEE);
    address internal upgradeAdmin = address(0xBABE);

    // Roles (same as in the contract, for convenience)
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function setUp() public {
        // Deploy mock tokens
        mockToken1 = new ERC20Mock();
        mockToken2 = new ERC20Mock();

        mockToken1.mint(address(this), 1_000_000 ether);
        mockToken2.mint(address(this), 2_000_000 ether);

        // Deploy mock RewardsController and EmissionManager
        mockRewardsController = new MockRewardsController();
        mockEmissionManager = new MockEmissionManager(address(mockRewardsController));

        // Deploy mockPool with two reserve tokens
        address[] memory reserves = new address[](2);
        reserves[0] = address(mockToken1);
        reserves[1] = address(mockToken2);
        mockPool = new MockPool(reserves, treasury);

        mockPool.setReserveData(address(mockToken1), address(mockToken1));
        mockPool.setReserveData(address(mockToken2), address(mockToken2));

        RewardKeeper implementation = new RewardKeeper();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                implementation.initialize.selector,
                address(mockPool),
                address(mockEmissionManager),
                admin,
                treasury,
                address(mockToken1)
            )
        );
        rewardKeeper = RewardKeeper(address(proxy));

        // Give admin the UPGRADER_ROLE for testing upgrades
        vm.startPrank(admin);
        rewardKeeper.grantRole(UPGRADER_ROLE, upgradeAdmin);
        
        vm.stopPrank();
    }

    function testInitializeSetsValues() public {
        // Check storage layout values
        StorageLib.Layout memory layout = rewardKeeper.getLayout();

        assertEq(address(layout.manager), address(mockEmissionManager), "manager mismatch");
        assertEq(address(layout.pool), address(mockPool), "pool mismatch");
        assertEq(address(layout.controller), address(mockRewardsController), "controller mismatch");
        assertEq(layout.treasury, treasury, "treasury mismatch");
        assertEq(layout.rewardAdmin, address(this), "reward admin mismatch");
        assertEq(layout.period, 1 days, "wrong period");
        assertEq(layout.lastClaim, block.timestamp, "Wrong last claim");
        assertEq(layout.asset, address(mockToken1), "asset mismatch");
    }

    function testOnlyManagerCanSetPool() public {
        
        vm.expectRevert(); // revert due to missing MANAGER_ROLE
        rewardKeeper.setPool(address(0xABC));

        vm.prank(admin);
        rewardKeeper.setPool(address(0xABC));

        StorageLib.Layout memory layout = rewardKeeper.getLayout();
        assertEq(address(layout.pool), address(0xABC), "Pool not updated");
    }

    function testOnlyManagerCanSetTreasury() public {
        vm.expectRevert();
        rewardKeeper.setTreasury(address(0xDEF));

        vm.prank(admin);
        rewardKeeper.setTreasury(address(0xDEF));

        StorageLib.Layout memory layout = rewardKeeper.getLayout();
        assertEq(layout.treasury, address(0xDEF), "Treasury not updated");
    }

    function testOnlyManagerCanSetPeriod() public {
        vm.expectRevert();
        rewardKeeper.setPeriod(2 days);

        vm.prank(admin);
        rewardKeeper.setPeriod(2 days);

        StorageLib.Layout memory layout = rewardKeeper.getLayout();
        assertEq(layout.period, 2 days, "Period not updated");
    }

    function testOnlyManagerCanSetRewardAdmin() public {
        vm.expectRevert();
        rewardKeeper.setRewardAdmin(address(0xFAFA));

        vm.prank(admin);
        rewardKeeper.setRewardAdmin(address(0xFAFA));

        StorageLib.Layout memory layout = rewardKeeper.getLayout();
        assertEq(layout.rewardAdmin, address(0xFAFA), "RewardAdmin not updated");
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
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.InvalidPeriod.selector));
        rewardKeeper.setPeriod(0);
    }

    function testSetEmissionManagerRevertsWhenZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.isZeroAddress.selector, address(0)));
        rewardKeeper.setEmissionManager(address(0));
    }

    function testSetPoolRevertsWhenZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.isZeroAddress.selector, address(0)));
        rewardKeeper.setPool(address(0));
    }

    function testSetTreasuryRevertsWhenZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.isZeroAddress.selector, address(0)));
        rewardKeeper.setTreasury(address(0));
    }

    function testSetRewardAdminRevertsWhenZero() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.isZeroAddress.selector, address(0)));
        rewardKeeper.setRewardAdmin(address(0));
    }

    function testClaimAndSetRateRevertsIfNotEnoughTimePassed() public {
        // will never have block.timestamp = 1. This would cause math issues. So warp to the future.
        vm.warp(block.timestamp + 5000 days);

        vm.startPrank(address(this));
        rewardKeeper.claimAndSetRate();
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.InsufficientTimeElapsed.selector));
        rewardKeeper.claimAndSetRate();
    }

    function testClaimAndSetRateSucceedsIfPeriodElapsed() public {
        // Wait 1 day to surpass the period
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(address(this));
        rewardKeeper.claimAndSetRate();

        // Check that lastClaim updated
        StorageLib.Layout memory layout = rewardKeeper.getLayout();
        assertEq(layout.lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(layout.previousPeriod, 1 days, "previousPeriod mismatch after claim");
    }

    function testClaimAndSetRateWithChangingPeriods() public {
        // Wait 1 day to surpass the period
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(address(this));
        rewardKeeper.claimAndSetRate();

        // Check that lastClaim updated
        StorageLib.Layout memory layout = rewardKeeper.getLayout();
        assertEq(layout.lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(layout.previousPeriod, 1 days, "previousPeriod mismatch after claim");

        vm.prank(admin);
        rewardKeeper.setPeriod(3 days);
        layout = rewardKeeper.getLayout();
        assertEq(layout.period, 3 days, "period incorrect");
        assertEq(layout.previousPeriod, 1 days, "previousPeriod should not change");

        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.InsufficientTimeElapsed.selector));
        rewardKeeper.claimAndSetRate();

        vm.warp(block.timestamp + 1 hours);
        rewardKeeper.claimAndSetRate();
        layout = rewardKeeper.getLayout();
        assertEq(layout.period, 3 days, "period incorrect");
        assertEq(layout.previousPeriod, 3 days, "previousPeriod should not change");

        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(abi.encodeWithSelector(RewardKeeper.InsufficientTimeElapsed.selector));
        rewardKeeper.claimAndSetRate();

        vm.warp(block.timestamp + 1 days);
        rewardKeeper.claimAndSetRate();
    }

    function testClaimAndSetRateCreatesNewTransferStrategyIfNoneFound() public {
        // In the contract, if the controller returns address(0) for getTransferStrategy,
        // it deploys a new ERC20TransferStrategy. We can see that by checking
        // the mockRewardsController and ensuring a new strategy was set.

        // Wait 1 day
        vm.warp(block.timestamp + 1 days + 1);

        // Initially, no strategy for mockToken1 or mockToken2
        assertEq(mockRewardsController.getTransferStrategy(address(mockToken1)), address(0), "Should be no strategy");
        assertEq(mockRewardsController.getTransferStrategy(address(mockToken2)), address(0), "Should be no strategy");

        // call claimAndSetRate
        vm.prank(address(this));
        rewardKeeper.claimAndSetRate();

        // Now, each should have a newly created ERC20TransferStrategy
        address strategy1 = mockRewardsController.getTransferStrategy(address(mockToken1));
        address strategy2 = mockRewardsController.getTransferStrategy(address(mockToken2));

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
}