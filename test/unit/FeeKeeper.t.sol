// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {
    IFeeKeeper,
    FeeKeeper,
    UUPSUpgradeable,
    IFeeSource,
    IERC20,
    PausableUpgradeable,
    Initializable
} from "../../src/FeeKeeper.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockFeeSource} from "../mocks/MockFeeSource.sol";
import {ERC1967Proxy, ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RewardsController} from "aave-v3-periphery/contracts/rewards/RewardsController.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {InitializableAdminUpgradeabilityProxy} from
    "aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";
import {StakedToken} from "../../src/StakedToken.sol";
import {Constants} from "../../src/library/Constants.sol";
import {ERC20TransferStrategy} from "../../src/transfer-strategies/ERC20TransferStrategy.sol";
import {RewardsControllerUtils} from "../utils/RewardsControllerUtils.sol";

contract FeeKeeperTest is Test {
    FeeKeeper public feeKeeper;
    RewardsController public rewardsController;
    StakedToken public stkToken;
    MockERC20 public assetToken;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;
    MockOracle public oracle;
    MockFeeSource public feeSource1;
    MockFeeSource public feeSource2;

    address public admin;
    address public treasury;
    address public user;

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        treasury = makeAddr("treasury");
        user = makeAddr("user");

        assetToken = new MockERC20("SEAM Token", "SEAM", 18);

        // Deploy mock tokens
        StakedToken stakedTokenImplementation = new StakedToken();
        ERC1967Proxy stakedTokenProxy = new ERC1967Proxy(
            address(stakedTokenImplementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                address(assetToken),
                admin,
                "Staked SEAM", // "stakedSEAM",
                "stkSEAM", //"stkSEAM",
                7 days,
                1 days
            )
        );
        stkToken = StakedToken(address(stakedTokenProxy));

        rewardToken1 = new MockERC20("Reward Token 1", "RWD1", 18);
        rewardToken2 = new MockERC20("Reward Token 2", "RWD2", 18);

        // Deploy mock contracts
        oracle = new MockOracle();
        oracle.setPrice(1e8);

        // Deploy FeeKeeper through proxy
        FeeKeeper feeKeeperImplementation = new FeeKeeper();
        ERC1967Proxy feeKeeperProxy = new ERC1967Proxy(
            address(feeKeeperImplementation),
            abi.encodeWithSelector(FeeKeeper.initialize.selector, admin, address(stkToken), address(oracle))
        );
        feeKeeper = FeeKeeper(address(feeKeeperProxy));

        // Deploy RewardsController through proxy
        rewardsController = RewardsControllerUtils.deployRewardsController(address(feeKeeper), admin);

        // Setup fee sources
        feeSource1 = new MockFeeSource(rewardToken1);
        feeSource2 = new MockFeeSource(rewardToken2);

        // Setup roles
        vm.startPrank(admin);
        feeKeeper.setRewardsController(address(rewardsController));
        stkToken.setController(address(rewardsController));
        vm.stopPrank();
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(feeKeeper.getAsset(), address(stkToken));
        assertEq(address(feeKeeper.getOracle()), address(oracle));
        assertEq(feeKeeper.getPeriod(), 1 days);
        assertEq(feeKeeper.getLastClaim(), block.timestamp);

        assertTrue(feeKeeper.hasRole(feeKeeper.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(feeKeeper.hasRole(feeKeeper.MANAGER_ROLE(), admin));
        assertTrue(feeKeeper.hasRole(feeKeeper.REWARD_SETTER_ROLE(), admin));
        assertTrue(feeKeeper.hasRole(feeKeeper.UPGRADER_ROLE(), admin));

        // Check rewards controller is set correctly
        assertEq(address(feeKeeper.getController()), address(rewardsController));
        assertEq(address(stkToken.getRewardsController()), address(rewardsController));
    }

    function test_ImplementationInitializersDisabled() public {
        // Deploy a new implementation without proxy
        FeeKeeper implementation = new FeeKeeper();

        // Try to initialize the implementation directly
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(admin, address(stkToken), address(oracle));
    }

    // ============ Upgrade Tests ============

    function test_Upgrade() public {
        vm.startPrank(admin);

        // Deploy a new implementation
        FeeKeeper newImplementation = new FeeKeeper();

        // Upgrade to the new implementation
        vm.expectEmit(true, true, true, true);
        emit ERC1967Utils.Upgraded(address(newImplementation));
        feeKeeper.upgradeToAndCall(address(newImplementation), "");

        vm.stopPrank();
    }

    function test_RevertWhen_NonUpgraderUpgrades() public {
        vm.startPrank(user);

        // Deploy a new implementation
        FeeKeeper newImplementation = new FeeKeeper();

        // Attempt to upgrade without the UPGRADER_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.UPGRADER_ROLE()
            )
        );
        feeKeeper.upgradeToAndCall(address(newImplementation), "");

        vm.stopPrank();
    }

    // ============ Pause/Unpause Tests ============

    function test_Pause() public {
        vm.startPrank(admin);

        // Grant PAUSER_ROLE to admin
        feeKeeper.grantRole(feeKeeper.PAUSER_ROLE(), admin);

        // Verify contract is not paused initially
        assertFalse(feeKeeper.paused());

        // Pause the contract
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Paused(admin);
        feeKeeper.pause();

        // Verify contract is paused
        assertTrue(feeKeeper.paused());

        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.startPrank(admin);

        // Grant PAUSER_ROLE to admin
        feeKeeper.grantRole(feeKeeper.PAUSER_ROLE(), admin);

        // Pause the contract first
        feeKeeper.pause();
        assertTrue(feeKeeper.paused());

        // Unpause the contract
        vm.expectEmit(true, true, true, true);
        emit PausableUpgradeable.Unpaused(admin);
        feeKeeper.unpause();

        // Verify contract is not paused
        assertFalse(feeKeeper.paused());

        vm.stopPrank();
    }

    function test_RevertWhen_NonPauserPauses() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.PAUSER_ROLE()
            )
        );
        feeKeeper.pause();
        vm.stopPrank();
    }

    function test_RevertWhen_NonPauserUnpauses() public {
        // First pause the contract as admin
        vm.startPrank(admin);
        feeKeeper.grantRole(feeKeeper.PAUSER_ROLE(), admin);
        feeKeeper.pause();
        vm.stopPrank();

        // Try to unpause as non-pauser
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.PAUSER_ROLE()
            )
        );
        feeKeeper.unpause();
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimingWhilePaused() public {
        vm.startPrank(admin);

        // Add fee source
        feeKeeper.addFeeSource(feeSource1);

        // Grant PAUSER_ROLE to admin and pause
        feeKeeper.grantRole(feeKeeper.PAUSER_ROLE(), admin);
        feeKeeper.pause();

        vm.stopPrank();

        // Try to claim while paused
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        feeKeeper.claimAndSetRate();
    }

    // ============ Fee Source Management Tests ============

    function test_AddFeeSource() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, false, false);
        emit IFeeKeeper.FeeSourceAdded(address(feeSource1));
        feeKeeper.addFeeSource(feeSource1);

        vm.stopPrank();

        address[] memory sources = feeKeeper.getFeeSources();
        assertEq(sources.length, 1);
        assertEq(sources[0], address(feeSource1));
    }

    function test_AddMultipleFeeSources() public {
        vm.startPrank(admin);

        // Add first fee source
        vm.expectEmit(true, true, false, false);
        emit IFeeKeeper.FeeSourceAdded(address(feeSource1));
        feeKeeper.addFeeSource(feeSource1);

        // Add second fee source
        vm.expectEmit(true, true, false, false);
        emit IFeeKeeper.FeeSourceAdded(address(feeSource2));
        feeKeeper.addFeeSource(feeSource2);

        vm.stopPrank();

        // Verify all sources were added correctly
        address[] memory sources = feeKeeper.getFeeSources();
        assertEq(sources.length, 2);
        assertEq(sources[0], address(feeSource1));
        assertEq(sources[1], address(feeSource2));
    }

    function test_RevertWhen_NonManagerAddsSource() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.MANAGER_ROLE()
            )
        );
        feeKeeper.addFeeSource(feeSource1);
        vm.stopPrank();
    }

    function test_RevertWhen_AddingDuplicateFeeSourceToken() public {
        vm.startPrank(admin);

        // Add first fee source
        feeKeeper.addFeeSource(feeSource1);

        // Create a new fee source with the same token address
        MockFeeSource duplicateFeeSource = new MockFeeSource(rewardToken1);

        console.log("duplicateFeeSource token address:", address(duplicateFeeSource.token()));
        console.log("feeSource1 token address:", address(feeSource1.token()));

        // Attempt to add a fee source with the same token address
        vm.expectRevert(IFeeKeeper.FeeSourceTokenAlreadyExists.selector);
        feeKeeper.addFeeSource(duplicateFeeSource);

        vm.stopPrank();

        // Verify only the original fee source was added
        address[] memory sources = feeKeeper.getFeeSources();
        assertEq(sources.length, 1);
        assertEq(sources[0], address(feeSource1));
    }

    function test_RemoveFeeSource() public {
        vm.startPrank(admin);

        feeKeeper.addFeeSource(feeSource1);

        vm.expectEmit(true, false, false, false);
        emit IFeeKeeper.FeeSourceRemoved(address(feeSource1));
        feeKeeper.removeFeeSource(feeSource1);

        vm.stopPrank();

        address[] memory sources = feeKeeper.getFeeSources();
        assertEq(sources.length, 0);
    }

    function test_RemoveFeeSourceNotLast() public {
        vm.startPrank(admin);

        // Add two fee sources
        feeKeeper.addFeeSource(feeSource1);
        feeKeeper.addFeeSource(feeSource2);

        // Verify initial state
        address[] memory sourcesBefore = feeKeeper.getFeeSources();
        assertEq(sourcesBefore.length, 2);
        assertEq(sourcesBefore[0], address(feeSource1));
        assertEq(sourcesBefore[1], address(feeSource2));

        // Remove the first fee source (not the last in the array)
        vm.expectEmit(true, false, false, false);
        emit IFeeKeeper.FeeSourceRemoved(address(feeSource1));
        feeKeeper.removeFeeSource(feeSource1);

        // Verify the fee sources after removal
        address[] memory sourcesAfter = feeKeeper.getFeeSources();
        assertEq(sourcesAfter.length, 1);
        assertEq(sourcesAfter[0], address(feeSource2));

        vm.stopPrank();
    }

    function test_RevertWhen_NonManagerRemovesSource() public {
        vm.startPrank(admin);
        feeKeeper.addFeeSource(feeSource1);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.MANAGER_ROLE()
            )
        );
        feeKeeper.removeFeeSource(feeSource1);
        vm.stopPrank();
    }

    // ============ Claim and Rate Setting Tests ============

    function testFuzz_ClaimAndSetRate(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1 days, type(uint256).max);
        amount2 = bound(amount2, 1 days, type(uint256).max);

        vm.startPrank(admin);

        // Add fee sources
        feeKeeper.addFeeSource(feeSource1);
        feeKeeper.addFeeSource(feeSource2);

        // Mint tokens to fee sources
        rewardToken1.mint(address(feeSource1), amount1);
        rewardToken2.mint(address(feeSource2), amount2);

        // Set the claimable amounts
        feeSource1.setClaimableAmount(amount1);
        feeSource2.setClaimableAmount(amount2);

        vm.stopPrank();

        uint256 period = 1 days;

        // Move time forward to when period starts exactly
        vm.warp(block.timestamp + period - 1);

        // Perform claim
        feeKeeper.claimAndSetRate();

        // Verify state changes
        assertEq(feeKeeper.getLastClaim(), block.timestamp);
        assertEq(feeKeeper.getPreviousPeriod(), 1 days);

        // Check that ERC20TransferStrategy is deployed correctly
        address transferStrategy1 = rewardsController.getTransferStrategy(address(rewardToken1));
        address transferStrategy2 = rewardsController.getTransferStrategy(address(rewardToken2));

        assertTrue(transferStrategy1 != address(0));
        assertTrue(transferStrategy2 != address(0));

        // Verify the transfer strategies are correctly configured
        ERC20TransferStrategy strategy1 = ERC20TransferStrategy(transferStrategy1);
        ERC20TransferStrategy strategy2 = ERC20TransferStrategy(transferStrategy2);

        assertEq(address(strategy1.rewardToken()), address(rewardToken1));
        assertEq(address(strategy1.getIncentivesController()), address(rewardsController));
        assertEq(address(strategy1.getRewardsAdmin()), address(feeKeeper));

        assertEq(address(strategy2.rewardToken()), address(rewardToken2));
        assertEq(address(strategy2.getIncentivesController()), address(rewardsController));
        assertEq(address(strategy2.getRewardsAdmin()), address(feeKeeper));

        // Calculate expected emission rates
        uint88 expectedEmissionRate1 = uint88(amount1 / period);
        uint88 expectedEmissionRate2 = uint88(amount2 / period);

        // Check distribution end and emission per second values
        (, uint256 emissionPerSecond1,, uint256 distributionEnd1) =
            rewardsController.getRewardsData(address(stkToken), address(rewardToken1));
        (, uint256 emissionPerSecond2,, uint256 distributionEnd2) =
            rewardsController.getRewardsData(address(stkToken), address(rewardToken2));

        assertEq(emissionPerSecond1, expectedEmissionRate1);
        assertEq(distributionEnd1, block.timestamp + period);

        assertEq(emissionPerSecond2, expectedEmissionRate2);
        assertEq(distributionEnd2, block.timestamp + period);

        // Check that transfer strategies have the correct balance of reward tokens
        assertEq(rewardToken1.balanceOf(transferStrategy1), expectedEmissionRate1 * period);
        assertEq(rewardToken2.balanceOf(transferStrategy2), expectedEmissionRate2 * period);
    }

    function test_ClaimAndSetRateWithExistingTransferStrategy() public {
        vm.startPrank(admin);

        // Add fee source
        feeKeeper.addFeeSource(feeSource1);

        // Set claimable amount
        uint256 amount = 1000 ether;
        rewardToken1.mint(address(feeSource1), amount);
        feeSource1.setClaimableAmount(amount);

        vm.stopPrank();

        // First claim to create the transfer strategy
        feeKeeper.claimAndSetRate();

        uint256 period1 = feeKeeper.getPreviousPeriod();

        // Get the transfer strategy address after first claim
        address originalTransferStrategy = rewardsController.getTransferStrategy(address(rewardToken1));
        assertTrue(originalTransferStrategy != address(0));

        // Set up for second claim
        vm.startPrank(admin);
        uint256 secondAmount = 500 ether;
        rewardToken1.mint(address(feeSource1), secondAmount);
        feeSource1.setClaimableAmount(secondAmount);
        vm.stopPrank();

        // Move time forward one day
        vm.warp(block.timestamp + 1 days - 1);

        // Perform second claim
        feeKeeper.claimAndSetRate();

        // Verify the transfer strategy address hasn't changed
        address newTransferStrategy = rewardsController.getTransferStrategy(address(rewardToken1));
        assertEq(newTransferStrategy, originalTransferStrategy);

        // Verify the emission rate was updated
        uint256 period = feeKeeper.getPeriod();
        uint88 expectedEmissionRate = uint88(secondAmount / period);
        (, uint256 emissionPerSecond,,) = rewardsController.getRewardsData(address(stkToken), address(rewardToken1));
        assertEq(emissionPerSecond, expectedEmissionRate);

        // Verify the transfer strategy received the new tokens
        assertEq(
            rewardToken1.balanceOf(originalTransferStrategy),
            (uint88(amount / period1) * period1) + (expectedEmissionRate * period)
        );
    }

    function test_ClaimAndSetRateAfterSkippingPeriod() public {
        vm.startPrank(admin);

        // Add fee source
        feeKeeper.addFeeSource(feeSource1);

        // Set claimable amount
        uint256 amount = 1000 ether;
        rewardToken1.mint(address(feeSource1), amount);
        feeSource1.setClaimableAmount(amount);

        vm.stopPrank();

        // Skip more than one period (2 days)
        vm.warp(block.timestamp + 2 days - 1);

        // Perform claim
        feeKeeper.claimAndSetRate();

        // Verify the lastClaim timestamp was updated
        assertEq(feeKeeper.getLastClaim(), block.timestamp);

        // Verify the previousPeriod was set correctly
        uint256 period = feeKeeper.getPeriod();
        assertEq(feeKeeper.getPreviousPeriod(), period);

        (, uint256 emissionPerSecond,, uint256 distributionEnd) =
            rewardsController.getRewardsData(address(stkToken), address(rewardToken1));

        // Verify the emission rate was set correctly
        uint88 expectedEmissionRate = uint88(amount / period);
        assertEq(emissionPerSecond, expectedEmissionRate);

        // Verify the distribution end time was set correctly
        assertEq(distributionEnd, block.timestamp + period);
    }

    function testFuzz_ClaimAndSetRateWithDifferentTimeElapsed(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 1 days);

        feeKeeper.claimAndSetRate();

        vm.startPrank(admin);

        // Add fee source
        feeKeeper.addFeeSource(feeSource1);

        // Set claimable amount
        uint256 amount = 1000 ether;
        rewardToken1.mint(address(feeSource1), amount);
        feeSource1.setClaimableAmount(amount);

        vm.stopPrank();

        // Warp time by the fuzzed amount
        vm.warp(block.timestamp + 1 days - 1 + timeElapsed);

        // Perform claim
        feeKeeper.claimAndSetRate();

        // Verify the lastClaim timestamp was updated
        assertEq(feeKeeper.getLastClaim(), block.timestamp);

        // Verify the previousPeriod was set correctly
        uint256 expectedPreviousPeriod = timeElapsed == 1 days ? 1 days : 1 days - timeElapsed;
        assertEq(feeKeeper.getPreviousPeriod(), expectedPreviousPeriod);

        (, uint256 emissionPerSecond,, uint256 distributionEnd) =
            rewardsController.getRewardsData(address(stkToken), address(rewardToken1));

        // Verify the emission rate was set correctly
        uint88 expectedEmissionRate = uint88(amount / expectedPreviousPeriod);
        assertEq(emissionPerSecond, expectedEmissionRate);

        // Verify the distribution end time was set correctly
        assertEq(distributionEnd, block.timestamp + expectedPreviousPeriod);
    }

    function test_ClaimAndSetRateWithZeroBalance() public {
        vm.startPrank(admin);

        // Add fee sources
        feeKeeper.addFeeSource(feeSource1);

        vm.stopPrank();

        // Set one source to have zero claimable amount
        feeSource1.setClaimableAmount(0);

        // Move time forward one day
        vm.warp(block.timestamp + 1 days);

        // Perform claim
        feeKeeper.claimAndSetRate();

        // Verify state changes
        assertEq(feeKeeper.getLastClaim(), block.timestamp);

        // Check that the token with zero balance was skipped
        (, uint256 emissionPerSecond1,,) = rewardsController.getRewardsData(address(stkToken), address(rewardToken1));

        assertEq(emissionPerSecond1, 0);
    }

    function test_ClaimAndSetRateWithZeroEmissionRate() public {
        vm.startPrank(admin);

        // Add fee sources
        feeKeeper.addFeeSource(feeSource1);

        // Set claimable amount
        rewardToken1.mint(address(feeSource1), 1);
        feeSource1.setClaimableAmount(1);

        // Set a very long period to make emission rate zero due to rounding
        feeKeeper.setPeriod(type(uint32).max);

        vm.stopPrank();

        // Move time forward
        vm.warp(block.timestamp + 1);

        // Perform claim
        feeKeeper.claimAndSetRate();

        // Verify state changes
        assertEq(feeKeeper.getLastClaim(), block.timestamp);

        // Check that the emission rate is zero
        (, uint256 emissionPerSecond,,) = rewardsController.getRewardsData(address(stkToken), address(rewardToken1));

        assertEq(emissionPerSecond, 0);
    }

    function test_RevertWhen_ClaimingTooSoon() public {
        // First claim
        vm.warp(block.timestamp + 1 days);
        feeKeeper.claimAndSetRate();

        // Try to claim again immediately
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.InsufficientTimeElapsed.selector));
        feeKeeper.claimAndSetRate();
    }

    function test_ClaimAndSetRateAfterPeriodChange() public {
        // First claim with default period
        vm.warp(block.timestamp + 1 days);
        feeKeeper.claimAndSetRate();

        // Change the period
        uint256 newPeriod = 2 days;
        vm.prank(admin);
        feeKeeper.setPeriod(newPeriod);

        assertEq(feeKeeper.getPeriod(), newPeriod);

        vm.warp(block.timestamp + 1 days - 1);

        feeKeeper.claimAndSetRate();

        assertEq(feeKeeper.getLastClaim(), block.timestamp);
        assertEq(feeKeeper.getPreviousPeriod(), newPeriod);

        // Move time forward by another day
        vm.warp(block.timestamp + 1 days);

        // Perform claim with new period
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.InsufficientTimeElapsed.selector));
        feeKeeper.claimAndSetRate();

        vm.warp(block.timestamp + 1 days);
        feeKeeper.claimAndSetRate();

        // Verify state changes
        assertEq(feeKeeper.getLastClaim(), block.timestamp);
        assertEq(feeKeeper.getPreviousPeriod(), newPeriod);
    }

    // ============ Period Management Tests ============

    function test_SetPeriod() public {
        vm.startPrank(admin);

        uint256 newPeriod = 2 days;

        vm.expectEmit(false, false, false, true);
        emit IFeeKeeper.SetPeriod(newPeriod);
        feeKeeper.setPeriod(newPeriod);

        assertEq(feeKeeper.getPeriod(), newPeriod);

        vm.stopPrank();
    }

    function test_RevertWhen_NonManagerSetsPeroid() public {
        vm.startPrank(user);

        uint256 newPeriod = 2 days;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.MANAGER_ROLE()
            )
        );
        feeKeeper.setPeriod(newPeriod);

        vm.stopPrank();
    }

    function test_RevertWhen_SettingZeroPeriod() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.InvalidPeriod.selector));
        feeKeeper.setPeriod(0);
        vm.stopPrank();
    }

    // ============ Asset Configuration Tests ============

    function test_ConfigureAsset() public {
        vm.startPrank(admin);

        // Setup parameters
        uint88 rate = 10e18;
        uint32 distributionEnd = uint32(block.timestamp + 30 days);
        address transferStrategy =
            address(new ERC20TransferStrategy(rewardToken1, address(rewardsController), address(feeKeeper)));

        // Allow token for manual rate
        feeKeeper.setTokenForManualRate(address(rewardToken1), true);

        // Configure asset
        feeKeeper.configureAsset(address(rewardToken1), rate, distributionEnd, transferStrategy, address(oracle));

        vm.stopPrank();

        // Verify configuration through RewardsController
        assertEq(rewardsController.getTransferStrategy(address(rewardToken1)), transferStrategy);

        // Verify emission rate
        (, uint256 emissionPerSecond,, uint256 distributionEndTimestamp) =
            rewardsController.getRewardsData(address(stkToken), address(rewardToken1));

        assertEq(emissionPerSecond, rate);
        assertEq(distributionEndTimestamp, distributionEnd);

        // Verify oracle is set correctly
        assertEq(address(rewardsController.getRewardOracle(address(rewardToken1))), address(oracle));
    }

    function test_RevertWhen_ConfiguringAssetWithoutPermission() public {
        // Setup parameters
        address rewardToken = address(rewardToken1);
        uint88 rate = 10e18;
        uint32 distributionEnd = uint32(block.timestamp + 30 days);
        address transferStrategy = makeAddr("transferStrategy");
        address oracleAddress = address(oracle);

        // Try to configure asset as non-admin
        vm.prank(user);
        vm.expectRevert();
        feeKeeper.configureAsset(rewardToken, rate, distributionEnd, transferStrategy, oracleAddress);
    }

    function test_RevertWhen_ConfiguringAssetNotAllowedForManualRate() public {
        vm.startPrank(admin);

        // Setup parameters
        address rewardToken = address(rewardToken1);
        uint88 rate = 10e18;
        uint32 distributionEnd = uint32(block.timestamp + 30 days);
        address transferStrategy = makeAddr("transferStrategy");
        address oracleAddress = address(oracle);

        // Make sure token is not allowed for manual rate
        feeKeeper.setTokenForManualRate(rewardToken, false);

        // Try to configure asset not allowed for manual rate
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.SetManualRateNotAuthorized.selector));
        feeKeeper.configureAsset(rewardToken, rate, distributionEnd, transferStrategy, oracleAddress);

        vm.stopPrank();
    }

    // ============ Token Management Tests ============

    function test_WithdrawTokens() public {
        uint256 amount = 100e18;
        rewardToken1.mint(address(feeKeeper), amount);

        vm.startPrank(admin);

        uint256 treasuryBalanceBefore = rewardToken1.balanceOf(treasury);

        vm.expectEmit(true, true, false, true);
        emit IFeeKeeper.WithdrawTokens(address(rewardToken1), treasury, amount);
        feeKeeper.withdrawTokens(address(rewardToken1), treasury, amount);

        assertEq(rewardToken1.balanceOf(treasury), treasuryBalanceBefore + amount, "Treasury should receive tokens");

        vm.stopPrank();
    }

    function test_RevertWhen_NonManagerWithdraws() public {
        vm.prank(user);
        vm.expectRevert();
        feeKeeper.withdrawTokens(address(rewardToken1), treasury, 100e18);
    }

    // ============ Manual Rate Management Tests ============

    function test_SetTokenForManualRate() public {
        vm.startPrank(admin);

        feeKeeper.setTokenForManualRate(address(rewardToken1), true);
        assertTrue(
            feeKeeper.getIsAllowedForManualRate(address(rewardToken1)), "Token should be allowed for manual rate"
        );

        feeKeeper.setTokenForManualRate(address(rewardToken1), false);
        assertFalse(
            feeKeeper.getIsAllowedForManualRate(address(rewardToken1)), "Token should not be allowed for manual rate"
        );

        vm.stopPrank();
    }

    function test_SetManualRate() public {
        vm.startPrank(admin);

        feeKeeper.setTokenForManualRate(address(rewardToken1), true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken1);

        uint88[] memory rates = new uint88[](1);
        rates[0] = 100;

        // Configure asset first
        address transferStrategy =
            address(new ERC20TransferStrategy(rewardToken1, address(rewardsController), address(feeKeeper)));
        uint32 distributionEnd = uint32(block.timestamp + 30 days);
        feeKeeper.configureAsset(address(rewardToken1), 0, distributionEnd, transferStrategy, address(oracle));

        // Then set manual rate
        feeKeeper.setManualRate(tokens, rates);

        vm.stopPrank();

        // Verify the emission rate was set correctly
        address[] memory rewardsList = new address[](1);
        rewardsList[0] = address(rewardToken1);

        (, uint256 emissionPerSecond,,) = rewardsController.getRewardsData(address(stkToken), address(rewardToken1));

        assertEq(emissionPerSecond, 100, "Emission per second should match the set rate");
    }

    function test_RevertWhen_SettingUnauthorizedManualRate() public {
        vm.startPrank(admin);

        address[] memory tokens = new address[](1);
        tokens[0] = address(rewardToken1);

        uint88[] memory rates = new uint88[](1);
        rates[0] = 100;

        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.SetManualRateNotAuthorized.selector));
        feeKeeper.setManualRate(tokens, rates);

        vm.stopPrank();
    }

    function test_SetManualDistributionEnd() public {
        vm.startPrank(admin);

        feeKeeper.setTokenForManualRate(address(rewardToken1), true);

        // Configure asset first
        address transferStrategy =
            address(new ERC20TransferStrategy(rewardToken1, address(rewardsController), address(feeKeeper)));
        uint32 initialDistributionEnd = uint32(block.timestamp + 30 days);
        feeKeeper.configureAsset(address(rewardToken1), 0, initialDistributionEnd, transferStrategy, address(oracle));

        // Then set manual distribution end
        feeKeeper.setManualDistributionEnd(address(rewardToken1), initialDistributionEnd);

        vm.stopPrank();

        // Verify the distribution end was set correctly
        (,,, uint256 distributionEnd) = rewardsController.getRewardsData(address(stkToken), address(rewardToken1));

        assertEq(distributionEnd, initialDistributionEnd, "Distribution end should match the set value");
    }

    function test_RevertWhen_SettingUnauthorizedManualDistributionEnd() public {
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.REWARD_SETTER_ROLE()
            )
        );
        feeKeeper.setManualDistributionEnd(address(rewardToken1), uint32(block.timestamp + 60 days));

        vm.stopPrank();
    }

    // ============ Transfer Strategy Tests ============

    function test_SetTransferStrategy() public {
        vm.startPrank(admin);

        // First allow the token for manual rate
        feeKeeper.setTokenForManualRate(address(rewardToken1), true);

        // Create a new transfer strategy
        address transferStrategy =
            address(new ERC20TransferStrategy(rewardToken1, address(rewardsController), address(feeKeeper)));

        // Set the transfer strategy
        feeKeeper.setTransferStrategy(address(rewardToken1), transferStrategy);

        vm.stopPrank();

        // Verify the transfer strategy was set correctly
        address setStrategy = rewardsController.getTransferStrategy(address(rewardToken1));
        assertEq(setStrategy, transferStrategy, "Transfer strategy should be set correctly");
    }

    function test_RevertWhen_NonRewardSetterSetsTransferStrategy() public {
        vm.startPrank(user);

        address transferStrategy =
            address(new ERC20TransferStrategy(rewardToken1, address(rewardsController), address(feeKeeper)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.REWARD_SETTER_ROLE()
            )
        );
        feeKeeper.setTransferStrategy(address(rewardToken1), transferStrategy);

        vm.stopPrank();
    }

    function test_RevertWhen_SettingTransferStrategyForUnauthorizedToken() public {
        vm.startPrank(admin);

        // Create a new transfer strategy but don't authorize the token
        address transferStrategy =
            address(new ERC20TransferStrategy(rewardToken1, address(rewardsController), address(feeKeeper)));

        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.SetManualRateNotAuthorized.selector));
        feeKeeper.setTransferStrategy(address(rewardToken1), transferStrategy);

        vm.stopPrank();
    }

    // ============ Set Claimer Tests ============

    function test_SetClaimer() public {
        address someUser = makeAddr("someUser");
        address someClaimer = makeAddr("claimer");

        // Set claimer for user
        vm.prank(admin);
        feeKeeper.setClaimer(someUser, someClaimer);

        // Verify the claimer was set correctly
        address setClaimer = rewardsController.getClaimer(someUser);
        assertEq(setClaimer, someClaimer, "Claimer should be set correctly");
    }

    function test_RevertWhen_NonManagerSetsClaimer() public {
        vm.startPrank(user);

        address someUser = makeAddr("someUser");
        address someClaimer = makeAddr("someClaimer");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.MANAGER_ROLE()
            )
        );
        feeKeeper.setClaimer(someUser, someClaimer);

        vm.stopPrank();
    }

    function test_SetClaimerToZeroAddress() public {
        address someUser = makeAddr("someUser");
        address claimer = makeAddr("claimer");

        // First set a claimer
        vm.prank(admin);
        feeKeeper.setClaimer(someUser, claimer);
        assertEq(rewardsController.getClaimer(someUser), claimer, "Claimer should be set correctly");

        // Then remove it by setting to zero address
        vm.prank(admin);
        feeKeeper.setClaimer(someUser, address(0));
        assertEq(rewardsController.getClaimer(someUser), address(0), "Claimer should be reset to zero address");
    }

    // ============ Emergency Withdrawal Tests ============

    function test_EmergencyWithdrawalFromTransferStrategy() public {
        vm.startPrank(admin);

        // First allow the token for manual rate
        feeKeeper.setTokenForManualRate(address(rewardToken1), true);

        // Create a new transfer strategy
        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(rewardToken1, address(rewardsController), address(feeKeeper));

        // Set the transfer strategy
        feeKeeper.setTransferStrategy(address(rewardToken1), address(transferStrategy));

        // Fund the transfer strategy
        uint256 amount = 100e18;
        rewardToken1.mint(address(transferStrategy), amount);

        // Perform emergency withdrawal
        address recipient = makeAddr("recipient");
        feeKeeper.emergencyWithdrawalFromTransferStrategy(address(rewardToken1), recipient, amount);

        // Verify the tokens were transferred to the recipient
        assertEq(rewardToken1.balanceOf(recipient), amount, "Recipient should have received the tokens");
        assertEq(rewardToken1.balanceOf(address(transferStrategy)), 0, "Transfer strategy should have 0 balance");

        vm.stopPrank();
    }

    function test_RevertWhen_NonManagerCallsEmergencyWithdrawal() public {
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, feeKeeper.MANAGER_ROLE()
            )
        );
        feeKeeper.emergencyWithdrawalFromTransferStrategy(address(rewardToken1), address(this), 100);

        vm.stopPrank();
    }

    function test_RevertWhen_EmergencyWithdrawalWithNoTransferStrategy() public {
        vm.startPrank(admin);

        // Try to withdraw from a token that doesn't have a transfer strategy set
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.TransferStrategyNotSet.selector));
        feeKeeper.emergencyWithdrawalFromTransferStrategy(address(rewardToken2), address(this), 100);

        vm.stopPrank();
    }

    // ============ Zero Address Tests ============

    function test_RevertWhen_AddingZeroAddressFeeSource() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.addFeeSource(IFeeSource(address(0)));
        vm.stopPrank();
    }

    function test_RevertWhen_RemovingZeroAddressFeeSource() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.removeFeeSource(IFeeSource(address(0)));
        vm.stopPrank();
    }

    function test_RevertWhen_SettingZeroAddressForManualRate() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.setTokenForManualRate(address(0), true);
        vm.stopPrank();
    }

    function test_RevertWhen_SettingZeroAddressTransferStrategy() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.setTransferStrategy(address(0), address(1));
        vm.stopPrank();
    }

    function test_RevertWhen_ConfiguringAssetWithZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.configureAsset(address(0), 100, uint32(block.timestamp + 1 days), address(1), address(1));
        vm.stopPrank();
    }

    function test_RevertWhen_SettingZeroAddressManualDistributionEnd() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.setManualDistributionEnd(address(0), uint32(block.timestamp + 1 days));
        vm.stopPrank();
    }

    function test_RevertWhen_EmergencyWithdrawalWithZeroAddresses() public {
        vm.startPrank(admin);

        // Test zero token address
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.emergencyWithdrawalFromTransferStrategy(address(0), address(1), 100);

        // Test zero recipient address
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.emergencyWithdrawalFromTransferStrategy(address(1), address(0), 100);
        vm.stopPrank();
    }

    function test_RevertWhen_SettingZeroAddressController() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IFeeKeeper.ZeroAddress.selector, address(0)));
        feeKeeper.setRewardsController(address(0));
        vm.stopPrank();
    }
}
