// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {
    Initializable,
    StakedToken,
    IStakedToken,
    PausableUpgradeable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    VotesUpgradeable
} from "../../src/StakedToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {ERC1967Proxy, ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {RewardsController} from "aave-v3-periphery/contracts/rewards/RewardsController.sol";
import {InitializableAdminUpgradeabilityProxy} from
    "aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";
import {RewardsControllerUtils} from "../utils/RewardsControllerUtils.sol";

contract StakedTokenTest is Test {
    StakedToken public stkToken;
    MockERC20 public asset;
    address public admin;
    address public user;
    RewardsController public rewardsController;

    uint256 constant COOLDOWN_SECONDS = 7 days;
    uint256 constant UNSTAKE_WINDOW = 1 days;

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        user = makeAddr("user");

        // Deploy mock token
        asset = new MockERC20("SEAM Token", "SEAM", 18);

        // Deploy StakedToken through proxy
        StakedToken implementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedToken.initialize.selector,
                address(asset),
                admin,
                "Staked SEAM",
                "stkSEAM",
                COOLDOWN_SECONDS,
                UNSTAKE_WINDOW
            )
        );
        stkToken = StakedToken(address(proxy));

        // Deploy RewardsController through proxy
        rewardsController = RewardsControllerUtils.deployRewardsController(address(stkToken), admin);

        // Setup roles and controllers
        vm.startPrank(admin);
        stkToken.setController(address(rewardsController));
        vm.stopPrank();

        // By default block.timestamp is 0, warp to after cooldown period and unstake window to prevent underflows.
        vm.warp(block.timestamp + COOLDOWN_SECONDS + UNSTAKE_WINDOW);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(stkToken.name(), "Staked SEAM");
        assertEq(stkToken.symbol(), "stkSEAM");
        assertEq(stkToken.decimals(), 18);
        assertEq(stkToken.asset(), address(asset));
        assertEq(stkToken.getCooldown(), COOLDOWN_SECONDS);
        assertEq(stkToken.getUnstakeWindow(), UNSTAKE_WINDOW);

        assertTrue(stkToken.hasRole(stkToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(stkToken.hasRole(stkToken.MANAGER_ROLE(), admin));
        assertTrue(stkToken.hasRole(stkToken.UPGRADER_ROLE(), admin));
        assertTrue(stkToken.hasRole(stkToken.PAUSER_ROLE(), admin));
    }

    function test_ImplementationInitializersDisabled() public {
        // Deploy a new implementation without proxy
        StakedToken implementation = new StakedToken();

        // Try to initialize the implementation directly
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(asset), admin, "Staked SEAM", "stkSEAM", COOLDOWN_SECONDS, UNSTAKE_WINDOW);
    }

    // ============ Upgrade Tests ============

    function test_Upgrade() public {
        // Deploy new implementation
        StakedToken newImplementation = new StakedToken();

        // Expect the Upgraded event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ERC1967Utils.Upgraded(address(newImplementation));

        // Upgrade
        vm.prank(admin);
        stkToken.upgradeToAndCall(address(newImplementation), "");
    }

    function test_RevertWhen_NonUpgraderUpgrades() public {
        StakedToken newImplementation = new StakedToken();

        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, stkToken.UPGRADER_ROLE()
            )
        );
        stkToken.upgradeToAndCall(address(newImplementation), "");

        vm.stopPrank();
    }

    // ============ Scaled Balance Tests ============

    function testFuzz_ScaledTotalSupply(uint256 amount) public {
        // Bound the amount to avoid overflow and unrealistic values
        amount = bound(amount, 1, 1e36);

        vm.startPrank(user);

        // Mint enough tokens to the user
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);

        assertEq(stkToken.scaledTotalSupply(), stkToken.totalSupply());

        vm.stopPrank();
    }

    function testFuzz_GetScaledUserBalanceAndSupply(uint256 amount) public {
        // Bound the amount to avoid overflow and unrealistic values
        amount = bound(amount, 1, 1e36);

        vm.startPrank(user);

        // Mint enough tokens to the user
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);

        (uint256 scaledBalance, uint256 scaledSupply) = stkToken.getScaledUserBalanceAndSupply(user);
        assertEq(scaledBalance, stkToken.balanceOf(user));
        assertEq(scaledSupply, stkToken.totalSupply());

        vm.stopPrank();
    }

    // ============ Pause/Unpause Tests ============

    function test_Pause() public {
        vm.startPrank(admin);

        assertFalse(stkToken.paused());

        stkToken.pause();
        assertTrue(stkToken.paused());

        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.startPrank(admin);

        stkToken.pause();
        assertTrue(stkToken.paused());

        stkToken.unpause();
        assertFalse(stkToken.paused());

        vm.stopPrank();
    }

    function test_RevertWhen_NonPauserPauses() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, stkToken.PAUSER_ROLE()
            )
        );
        stkToken.pause();
        vm.stopPrank();
    }

    function test_RevertWhen_NonPauserUnpauses() public {
        vm.prank(admin);
        stkToken.pause();

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, stkToken.PAUSER_ROLE()
            )
        );
        stkToken.unpause();
        vm.stopPrank();
    }

    // ============ Emergency Withdrawal Tests ============

    function testFuzz_EmergencyWithdrawal(uint256 amount) public {
        // Bound the amount to avoid overflow and unrealistic values
        amount = bound(amount, 1, stkToken.maxMint(address(0)));

        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount); // Ensure user has enough tokens
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);
        vm.stopPrank();

        // Emergency withdrawal
        address emergencyRecipient = makeAddr("emergencyRecipient");
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit IStakedToken.EmergencyWithdraw(emergencyRecipient, amount);
        stkToken.emergencyWithdrawal(emergencyRecipient, amount);

        assertEq(asset.balanceOf(emergencyRecipient), amount);
        assertEq(asset.balanceOf(address(stkToken)), 0);

        vm.stopPrank();
    }

    function test_RevertWhen_NonManagerCallsEmergencyWithdrawal() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, stkToken.MANAGER_ROLE()
            )
        );
        stkToken.emergencyWithdrawal(user, 100e18);
        vm.stopPrank();
    }

    // ============ Clock Tests ============

    function test_Clock() public view {
        assertEq(stkToken.clock(), uint48(block.timestamp));
    }

    function test_ClockMode() public view {
        assertEq(stkToken.CLOCK_MODE(), "mode=timestamp");
    }

    // ============ Cooldown Tests ============

    function test_Cooldown() public {
        uint256 amount = 100e18;
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        vm.expectEmit(true, true, true, true);
        emit IStakedToken.Cooldown(user);
        stkToken.cooldown();

        assertEq(stkToken.getStakerCooldown(user), block.timestamp);

        vm.stopPrank();
    }

    function test_RevertWhen_CooldownWithZeroBalance() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.InsufficientStake.selector));
        stkToken.cooldown();
        vm.stopPrank();
    }

    // ============ Get Next Cooldown Timestamp Tests ============

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_GetNextCooldownTimestamp_WithZeroToCooldown(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)));

        address recipient = makeAddr("recipient");

        vm.startPrank(user);

        // Setup initial state
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.cooldown();

        uint256 fromCooldownTimestamp = stkToken.getStakerCooldown(user);

        // Ensure recipient has no cooldown
        assertEq(stkToken.getStakerCooldown(recipient), 0);

        // Test getNextCooldownTimestamp with recipient having zero cooldown
        uint256 cooldownTimestamp = stkToken.getNextCooldownTimestamp(fromCooldownTimestamp, amount, recipient, 0);

        // When recipient has no cooldown, the function should return 0
        assertEq(cooldownTimestamp, 0);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function test_GetNextCooldownTimestamp_WithExpiredToCooldown(uint256 amount, uint256 recipientAmount) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        recipientAmount = bound(recipientAmount, 1, stkToken.maxMint(address(0)) - amount);

        address recipient = makeAddr("recipient");

        // Setup initial state for both user and recipient
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.cooldown();
        uint256 fromCooldownTimestamp = stkToken.getStakerCooldown(user);
        vm.stopPrank();

        // Setup recipient with a cooldown
        vm.startPrank(recipient);
        asset.mint(recipient, recipientAmount);
        asset.approve(address(stkToken), recipientAmount);
        stkToken.mint(recipientAmount, recipient);
        stkToken.cooldown();
        uint256 recipientCooldownTimestamp = stkToken.getStakerCooldown(recipient);
        assertEq(recipientCooldownTimestamp, block.timestamp);
        vm.stopPrank();

        // Warp time to make recipient's cooldown expired (past cooldown + unstake window)
        vm.warp(block.timestamp + COOLDOWN_SECONDS + UNSTAKE_WINDOW + 1);

        // Test getNextCooldownTimestamp with recipient having expired cooldown
        uint256 cooldownTimestamp =
            stkToken.getNextCooldownTimestamp(fromCooldownTimestamp, amount, recipient, stkToken.balanceOf(recipient));

        // When recipient's cooldown is expired, the function should return 0
        assertEq(cooldownTimestamp, 0);
    }

    /// forge-config: default.fuzz.runs = 1
    function test_GetNextCooldownTimestamp_FromCooldownLessThanToCooldown(
        uint256 amount,
        uint256 recipientAmount,
        uint32 warpAmount
    ) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        recipientAmount = bound(recipientAmount, 1, stkToken.maxMint(address(0)) - amount);
        warpAmount = uint32(bound(warpAmount, 1, COOLDOWN_SECONDS + UNSTAKE_WINDOW));
        address recipient = makeAddr("recipient");

        // Setup initial state for user (this will be the "from" address)
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.cooldown();
        uint256 fromCooldownTimestamp = stkToken.getStakerCooldown(user);
        vm.stopPrank();

        // Warp time to make user's cooldown expired (past cooldown + unstake window)
        vm.warp(block.timestamp + warpAmount);

        // Setup recipient with a fresh cooldown (this will be the "to" address)
        // This ensures recipient's cooldown is not expired
        vm.startPrank(recipient);
        asset.mint(recipient, recipientAmount);
        asset.approve(address(stkToken), recipientAmount);
        stkToken.mint(recipientAmount, recipient);
        stkToken.cooldown();
        uint256 recipientCooldownTimestamp = stkToken.getStakerCooldown(recipient);
        assertEq(recipientCooldownTimestamp, block.timestamp);
        vm.stopPrank();

        // Verify recipient's cooldown is still valid
        assertTrue(block.timestamp <= recipientCooldownTimestamp + COOLDOWN_SECONDS + UNSTAKE_WINDOW);

        // Test getNextCooldownTimestamp with:
        // - fromCooldownTimestamp that is expired
        // - recipient having a current, valid cooldown
        uint256 cooldownTimestamp =
            stkToken.getNextCooldownTimestamp(fromCooldownTimestamp, amount, recipient, stkToken.balanceOf(recipient));

        // When from's cooldown is expired but recipient's is valid,
        // the function should return the recipient's cooldown timestamp
        assertEq(cooldownTimestamp, recipientCooldownTimestamp);
    }

    function test_GetNextCooldownTimestamp_WeightedAverage(uint256 amount, uint256 recipientAmount) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        recipientAmount = bound(recipientAmount, 1, stkToken.maxMint(address(0)) - amount);

        address recipient = makeAddr("recipient");

        // Setup initial state for user (this will be the "from" address)
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.cooldown();
        uint256 fromCooldownTimestamp = stkToken.getStakerCooldown(user);
        vm.stopPrank();

        // Setup recipient with an existing balance and cooldown
        vm.startPrank(recipient);
        asset.mint(recipient, recipientAmount);
        asset.approve(address(stkToken), recipientAmount);
        stkToken.mint(recipientAmount, recipient);
        stkToken.cooldown();
        uint256 recipientCooldownTimestamp = stkToken.getStakerCooldown(recipient);
        vm.stopPrank();

        // Warp time forward but still within valid cooldown window for both
        vm.warp(block.timestamp + 1 days);

        // Calculate expected weighted average
        uint256 expectedCooldownTimestamp =
            (amount * fromCooldownTimestamp + recipientAmount * recipientCooldownTimestamp) / (amount + recipientAmount);

        // Test getNextCooldownTimestamp with both valid cooldowns
        uint256 actualCooldownTimestamp =
            stkToken.getNextCooldownTimestamp(fromCooldownTimestamp, amount, recipient, stkToken.balanceOf(recipient));

        // Verify the weighted average calculation
        assertEq(actualCooldownTimestamp, expectedCooldownTimestamp);

        // Verify it's between the two original timestamps
        assertTrue(
            actualCooldownTimestamp >= Math.min(fromCooldownTimestamp, recipientCooldownTimestamp)
                && actualCooldownTimestamp <= Math.max(fromCooldownTimestamp, recipientCooldownTimestamp)
        );
    }

    // ============ Deposit/Mint/Stake Tests ============

    function test_Mint(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)));
        vm.startPrank(user);

        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        uint256 shares = stkToken.mint(amount, user);

        assertEq(shares, amount);
        assertEq(stkToken.balanceOf(user), amount);
        assertEq(asset.balanceOf(address(stkToken)), amount);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function test_RevertWhen_MintingWhilePaused(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)));
        vm.prank(admin);
        stkToken.pause();

        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        stkToken.mint(amount, user);

        vm.stopPrank();
    }

    function test_MintWithActiveCooldown(uint256 amount, uint256 additionalAmount) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        additionalAmount = bound(additionalAmount, 1, stkToken.maxMint(address(0)) - amount);

        address recipient = makeAddr("recipient");

        // Setup recipient with an existing balance and cooldown
        vm.startPrank(recipient);
        asset.mint(recipient, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, recipient);
        stkToken.cooldown();
        uint256 initialCooldownTimestamp = stkToken.getStakerCooldown(recipient);
        vm.stopPrank();

        // Mint additional tokens to recipient
        vm.startPrank(user);
        asset.mint(user, additionalAmount);
        asset.approve(address(stkToken), additionalAmount);
        stkToken.mint(additionalAmount, recipient);
        vm.stopPrank();

        // Verify cooldown timestamp is preserved
        assertEq(stkToken.getStakerCooldown(recipient), initialCooldownTimestamp);
        assertEq(stkToken.balanceOf(recipient), amount + additionalAmount);
    }

    function test_DepositWithActiveCooldown(uint256 amount, uint256 additionalAmount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)) - 1);
        additionalAmount = bound(additionalAmount, 1, stkToken.maxDeposit(address(0)) - amount);

        // Setup user with an existing balance and cooldown
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);
        stkToken.cooldown();
        uint256 initialCooldownTimestamp = stkToken.getStakerCooldown(user);
        vm.stopPrank();

        // Deposit additional tokens to user
        vm.startPrank(user);
        asset.mint(user, additionalAmount);
        asset.approve(address(stkToken), additionalAmount);
        stkToken.deposit(additionalAmount, user);
        vm.stopPrank();

        // Verify cooldown timestamp is preserved
        assertEq(stkToken.getStakerCooldown(user), initialCooldownTimestamp);
        assertEq(stkToken.balanceOf(user), amount + additionalAmount);
    }

    function test_Deposit(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);

        stkToken.deposit(amount, user);

        assertEq(stkToken.balanceOf(user), amount);
        assertEq(asset.balanceOf(address(stkToken)), amount);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function test_RevertWhen_DepositingWhilePaused(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.prank(admin);
        stkToken.pause();

        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        stkToken.deposit(amount, user);

        vm.stopPrank();
    }

    // ============ Withdraw/Redeem/Unstake Tests ============

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_Withdraw_AfterCooldown(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Warp to after cooldown period but within unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        // Withdraw
        uint256 assets = stkToken.withdraw(amount, user, user);

        assertEq(assets, amount);
        assertEq(stkToken.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), amount);
        assertEq(asset.balanceOf(address(stkToken)), 0);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_RevertWhen_WithdrawBeforeCooldown(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Try to withdraw before cooldown period ends
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.CooldownStillActive.selector));
        stkToken.withdraw(amount, user, user);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_RevertWhen_WithdrawAfterUnstakeWindow(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Warp to after unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + UNSTAKE_WINDOW + 1);

        // Try to withdraw after unstake window
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.UnstakeWindowExpired.selector));
        stkToken.withdraw(amount, user, user);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_Redeem_AfterCooldown(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Warp to after cooldown period but within unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        // Redeem
        uint256 assets = stkToken.redeem(amount, user, user);

        assertEq(assets, amount);
        assertEq(stkToken.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), amount);
        assertEq(asset.balanceOf(address(stkToken)), 0);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_RevertWhen_RedeemBeforeCooldown(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Try to redeem before cooldown period ends
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.CooldownStillActive.selector));
        stkToken.redeem(amount, user, user);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_RevertWhen_RedeemAfterUnstakeWindow(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Warp to after unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + UNSTAKE_WINDOW + 1);

        // Try to redeem after unstake window
        vm.expectRevert(abi.encodeWithSelector(IStakedToken.UnstakeWindowExpired.selector));
        stkToken.redeem(amount, user, user);

        vm.stopPrank();
    }

    function testFuzz_PartialWithdraw(uint256 amount, uint256 withdrawRatio) public {
        amount = bound(amount, 2, stkToken.maxDeposit(address(0)));
        withdrawRatio = bound(withdrawRatio, 1, 99);
        uint256 withdrawAmount = (amount * withdrawRatio) / 100;

        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        assertEq(asset.balanceOf(user), amount, "Asset balance mismatch");
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Warp to after cooldown period but within unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        // Partial withdraw
        uint256 assets = stkToken.withdraw(withdrawAmount, user, user);

        assertEq(assets, withdrawAmount);
        assertEq(stkToken.balanceOf(user), amount - withdrawAmount);
        assertEq(asset.balanceOf(user), withdrawAmount);
        assertEq(asset.balanceOf(address(stkToken)), amount - withdrawAmount);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_WithdrawToOtherReceiver(uint256 amount) public {
        amount = bound(amount, 1, stkToken.maxDeposit(address(0)));
        address receiver = makeAddr("receiver");
        vm.startPrank(user);

        // First deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Initiate cooldown
        stkToken.cooldown();

        // Warp to after cooldown period but within unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        // Withdraw to different receiver
        uint256 assets = stkToken.withdraw(amount, receiver, user);

        assertEq(assets, amount);
        assertEq(stkToken.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), 0);
        assertEq(asset.balanceOf(receiver), amount);
        assertEq(asset.balanceOf(address(stkToken)), 0);

        vm.stopPrank();
    }

    // ============ Max Deposit/Supply Tests ============

    function test_MaxDeposit() public view {
        // MaxDeposit should return the max supply
        assertEq(stkToken.maxDeposit(address(0)), type(uint208).max);
        assertEq(stkToken.maxDeposit(user), type(uint208).max);
    }

    function test_MaxMint() public view {
        // MaxMint should also return the max supply
        assertEq(stkToken.maxMint(address(0)), type(uint208).max);
        assertEq(stkToken.maxMint(user), type(uint208).max);
    }

    function test_RevertWhen_DepositExceedsMaxDeposit() public {
        // Test deposit fails when exceeding max supply
        uint256 amount = type(uint208).max;
        amount += 1; // Exceed max supply by 1

        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);

        // Should revert as we're exceeding the max supply
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, user, amount, type(uint208).max
            )
        );
        stkToken.deposit(amount, user);

        vm.stopPrank();
    }

    // ============ ERC20Permit Tests ============

    /// forge-config: default.fuzz.runs = 1
    function test_Permit(uint256 amount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 1, stkToken.maxMint(address(0)));

        // Generate random owner address with private key
        (address owner, uint256 privateKey) = makeAddrAndKey("owner");
        address spender = makeAddr("spender");

        // Mint some tokens to the owner
        vm.startPrank(admin);
        asset.mint(owner, amount);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, owner);
        vm.stopPrank();

        // Check initial state
        assertEq(stkToken.allowance(owner, spender), 0);
        assertEq(stkToken.nonces(owner), 0);

        // Create permit data
        uint256 deadline = block.timestamp + 1 hours;

        // Get domain separator
        bytes32 DOMAIN_SEPARATOR = stkToken.DOMAIN_SEPARATOR();

        // Create the permit digest
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                stkToken.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Execute permit
        stkToken.permit(owner, spender, amount, deadline, v, r, s);

        // Verify state after permit
        assertEq(stkToken.allowance(owner, spender), amount);
        assertEq(stkToken.nonces(owner), 1);
    }

    /// forge-config: default.fuzz.runs = 1
    function test_RevertWhen_PermitExpired(uint256 amount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 1, stkToken.maxMint(address(0)));

        // Generate random owner address with private key
        (address owner, uint256 privateKey) = makeAddrAndKey("owner");
        address spender = makeAddr("spender");

        // Create permit data with expired deadline
        uint256 deadline = block.timestamp - 1;

        // Get domain separator
        bytes32 DOMAIN_SEPARATOR = stkToken.DOMAIN_SEPARATOR();

        // Create the permit digest
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                stkToken.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Execute permit - should revert due to expired deadline
        vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, deadline));
        stkToken.permit(owner, spender, amount, deadline, v, r, s);
    }

    /// forge-config: default.fuzz.runs = 1
    function test_RevertWhen_InvalidSignature(uint256 amount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 1, stkToken.maxMint(address(0)));

        // Generate random owner address with private key
        (address owner,) = makeAddrAndKey("owner");
        address spender = makeAddr("spender");

        // Generate a different key for invalid signature
        (address differentSigner, uint256 differentPrivateKey) = makeAddrAndKey("attacker");

        // Create permit data
        uint256 deadline = block.timestamp + 1 hours;

        // Create the permit digest
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                stkToken.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", stkToken.DOMAIN_SEPARATOR(), structHash));

        // Sign the digest with a different private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(differentPrivateKey, digest);

        // Execute permit - should revert due to invalid signature
        vm.expectRevert(
            abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, differentSigner, owner)
        );
        stkToken.permit(owner, spender, amount, deadline, v, r, s);
    }

    /// forge-config: default.fuzz.runs = 1
    function test_Nonces(uint256 amount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 1, stkToken.maxMint(address(0)));

        // Generate random owner address with private key
        (address owner, uint256 privateKey) = makeAddrAndKey("owner");
        address spender = makeAddr("spender");

        // Mint some tokens to the owner
        vm.startPrank(admin);
        asset.mint(owner, amount);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, owner);
        vm.stopPrank();

        // Check initial nonce
        assertEq(stkToken.nonces(owner), 0);

        // Create permit data
        uint256 deadline = block.timestamp + 1 hours;

        // Get domain separator
        bytes32 DOMAIN_SEPARATOR = stkToken.DOMAIN_SEPARATOR();

        // Create the permit digest for nonce 0
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                0, // nonce 0
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Execute permit
        stkToken.permit(owner, spender, amount, deadline, v, r, s);

        // Verify nonce increased
        assertEq(stkToken.nonces(owner), 1);

        // Try to use the same signature again (should fail due to nonce mismatch)
        vm.expectPartialRevert(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector);
        stkToken.permit(owner, spender, amount, deadline, v, r, s);

        // Nonce should still be 1
        assertEq(stkToken.nonces(owner), 1);
    }

    // ============ Admin Function Tests ============

    /// forge-config: default.fuzz.runs = 1
    function test_SetController(address newController) public {
        vm.assume(newController != address(0));

        vm.startPrank(admin);

        vm.expectEmit();
        emit IStakedToken.RewardsControllerSet(newController);
        stkToken.setController(newController);

        assertEq(address(stkToken.getRewardsController()), newController);

        vm.stopPrank();
    }

    function test_RevertWhen_NonManagerSetsController() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, stkToken.MANAGER_ROLE()
            )
        );
        stkToken.setController(address(rewardsController));
        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function test_SetTimers(uint256 newCooldown, uint256 newUnstakeWindow) public {
        vm.assume(newCooldown > 0 && newCooldown < 365 days);
        vm.assume(newUnstakeWindow > 0 && newUnstakeWindow < 30 days);

        vm.startPrank(admin);

        vm.expectEmit();
        emit IStakedToken.TimersSet(newCooldown, newUnstakeWindow);
        stkToken.setTimers(newCooldown, newUnstakeWindow);

        assertEq(stkToken.getCooldown(), newCooldown);
        assertEq(stkToken.getUnstakeWindow(), newUnstakeWindow);

        vm.stopPrank();
    }

    function test_RevertWhen_NonManagerSetsTimers() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, stkToken.MANAGER_ROLE()
            )
        );
        stkToken.setTimers(14 days, 2 days);
        vm.stopPrank();
    }

    // ============ Voting Tests ============

    function test_Delegate(uint256 amount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 1, stkToken.maxMint(address(0)));
        address delegate = makeAddr("delegate");

        vm.startPrank(user);

        // First mint some tokens
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);

        // Delegate voting power
        vm.expectEmit(true, true, true, false);
        emit IVotes.DelegateChanged(user, address(0), delegate);
        stkToken.delegate(delegate);

        assertEq(stkToken.delegates(user), delegate);
        assertEq(stkToken.getVotes(delegate), amount);

        vm.stopPrank();
    }

    function test_TransferWithDelegation(uint256 amount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 2, stkToken.maxMint(address(0)));
        address recipient = makeAddr("recipient");

        vm.startPrank(user);

        // First mint and delegate
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.delegate(user);

        // Transfer half the tokens
        uint256 transferAmount = amount / 2;
        stkToken.transfer(recipient, transferAmount);

        assertEq(stkToken.getVotes(user), amount - transferAmount);
        assertEq(stkToken.getVotes(recipient), 0);

        vm.stopPrank();
    }

    function test_VotingPowerWithZeroTotalSupply() public {
        // Voting power should be 0 when total supply is 0
        assertEq(stkToken.getVotes(user), 0);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), 0);
    }

    function test_VotingPowerWithAssetDonation(uint256 amount, uint256 donationAmount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        donationAmount = bound(donationAmount, 1, stkToken.maxMint(address(0)) - amount);

        vm.startPrank(user);

        // First mint and delegate
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.delegate(user);

        uint256 initialVotingPower = stkToken.getVotes(user);

        // Someone donates assets directly to vault
        vm.stopPrank();
        asset.mint(address(stkToken), donationAmount);

        // Voting power should remain unchanged until next checkpoint
        assertEq(stkToken.getVotes(user), initialVotingPower);

        // Trigger checkpoint via 0 deposit
        vm.startPrank(user);
        stkToken.deposit(0, user);

        // Voting power should now reflect increased asset balance
        assertEq(stkToken.getVotes(user), amount + donationAmount);

        vm.stopPrank();
    }

    function test_VotingPowerWithEmergencyWithdrawal(uint256 amount, uint256 withdrawAmount) public {
        // Bound amount to reasonable values, using maxMint as upper bound
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        withdrawAmount = bound(withdrawAmount, 1, amount);

        vm.startPrank(user);

        // First mint and delegate
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.delegate(user);

        assertEq(stkToken.getVotes(user), amount);

        vm.stopPrank();

        // Emergency withdraw half the assets
        vm.prank(admin);
        stkToken.emergencyWithdrawal(admin, withdrawAmount);

        // Voting power should be reduced proportionally
        assertEq(stkToken.getVotes(user), amount - withdrawAmount);
    }

    function test_PastVotingPowerWithAssetBalanceChanges(uint256 amount, uint256 donationAmount, uint256 withdrawAmount)
        public
    {
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        donationAmount = bound(donationAmount, 1, stkToken.maxMint(address(0)) - amount);
        withdrawAmount = bound(withdrawAmount, 1, amount + donationAmount);

        vm.startPrank(user);

        // Initial mint and delegate
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.delegate(user);

        assertEq(stkToken.getVotes(user), amount);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), 0);

        vm.warp(block.timestamp + 1);

        assertEq(stkToken.getVotes(user), amount);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), amount);

        // Direct asset donation
        vm.stopPrank();
        asset.mint(address(stkToken), donationAmount);

        // Voting power should not change until checkpoint
        assertEq(stkToken.getVotes(user), amount);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), amount);

        // Trigger checkpoint with 0 deposit
        vm.prank(user);
        stkToken.deposit(0, user);

        // Voting power should increase
        assertEq(stkToken.getVotes(user), amount + donationAmount);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), amount);

        vm.warp(block.timestamp + 1);

        assertEq(stkToken.getVotes(user), amount + donationAmount);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), amount + donationAmount);

        // Emergency withdrawal
        vm.prank(admin);
        stkToken.emergencyWithdrawal(admin, withdrawAmount);

        assertEq(stkToken.getVotes(user), amount + donationAmount - withdrawAmount);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), amount + donationAmount);

        vm.warp(block.timestamp + 1);

        assertEq(stkToken.getVotes(user), amount + donationAmount - withdrawAmount);
        assertEq(stkToken.getPastVotes(user, block.timestamp - 1), amount + donationAmount - withdrawAmount);
    }

    function test_GetPastAssetBalance(uint256 amount, uint256 donationAmount, uint256 withdrawAmount) public {
        amount = bound(amount, 1, stkToken.maxMint(address(0)) - 1);
        donationAmount = bound(donationAmount, 1, stkToken.maxMint(address(0)) - amount);
        withdrawAmount = bound(withdrawAmount, 1, amount + donationAmount);

        vm.startPrank(user);

        // Initial mint
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);

        assertEq(stkToken.getPastAssetBalance(block.timestamp - 1), 0);

        vm.warp(block.timestamp + 1);

        assertEq(stkToken.getPastAssetBalance(block.timestamp - 1), amount);

        // Direct asset donation
        vm.stopPrank();
        asset.mint(address(stkToken), donationAmount);

        // Asset balance should not change until checkpoint
        assertEq(stkToken.getPastAssetBalance(block.timestamp - 1), amount);

        // Trigger checkpoint with 0 deposit
        vm.prank(user);
        stkToken.deposit(0, user);

        vm.warp(block.timestamp + 1);

        assertEq(stkToken.getPastAssetBalance(block.timestamp - 1), amount + donationAmount);

        // Emergency withdrawal
        vm.prank(admin);
        stkToken.emergencyWithdrawal(admin, withdrawAmount);

        vm.warp(block.timestamp + 1);

        assertEq(stkToken.getPastAssetBalance(block.timestamp - 1), amount + donationAmount - withdrawAmount);
    }

    function test_GetPastAssetBalance_RevertsFutureLookup() public {
        vm.expectRevert(
            abi.encodeWithSelector(VotesUpgradeable.ERC5805FutureLookup.selector, block.timestamp, block.timestamp)
        );
        stkToken.getPastAssetBalance(block.timestamp);
    }

    // ============ Transfer Tests ============

    function test_TransferWithCooldown() public {
        uint256 amount = 100e18;
        address recipient = makeAddr("recipient");

        vm.startPrank(user);

        // First mint and start cooldown
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.cooldown();

        uint256 cooldownTimestamp = stkToken.getStakerCooldown(user);

        // Transfer half the tokens
        uint256 transferAmount = amount / 2;
        stkToken.transfer(recipient, transferAmount);

        // Check cooldown is maintained for remaining balance
        assertEq(stkToken.getStakerCooldown(user), cooldownTimestamp);
        assertEq(stkToken.getStakerCooldown(recipient), 0);

        vm.stopPrank();
    }

    function test_TransferEntireBalanceResetsCooldown() public {
        uint256 amount = 100e18;
        address recipient = makeAddr("recipient");

        vm.startPrank(user);

        // First mint and start cooldown
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.mint(amount, user);
        stkToken.cooldown();

        // Transfer entire balance
        stkToken.transfer(recipient, amount);

        assertEq(stkToken.getStakerCooldown(user), 0);
        assertEq(stkToken.getStakerCooldown(recipient), 0);

        vm.stopPrank();
    }

    // ============ HandleAction Tests ============

    function test_HandleActionOnDeposit(uint256 amount) public {
        // Bound amount to reasonable values using maxDeposit
        amount = bound(amount, 1e18, stkToken.maxDeposit(user));

        vm.startPrank(user);

        // Approve and prepare for deposit
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);

        // Expect handleAction to be called with correct parameters
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                IRewardsController.handleAction.selector,
                user,
                0, // totalSupply before deposit
                0 // oldUserBalance
            )
        );

        // Perform deposit
        stkToken.deposit(amount, user);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 10
    function test_HandleActionOnTransfer(uint256 amount) public {
        // Bound amount to reasonable values using maxDeposit
        amount = bound(amount, 2e18, stkToken.maxDeposit(user));
        address recipient = makeAddr("recipient");

        // First mint some tokens to user
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        uint256 transferAmount = amount / 2;
        uint256 totalSupply = stkToken.totalSupply();

        // Expect handleAction to be called for sender
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                IRewardsController.handleAction.selector,
                user,
                totalSupply,
                amount // oldUserBalance
            )
        );

        // Expect handleAction to be called for recipient
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                IRewardsController.handleAction.selector,
                recipient,
                totalSupply,
                0 // oldUserBalance
            )
        );

        // Perform transfer
        stkToken.transfer(recipient, transferAmount);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 10
    function test_HandleActionOnRedeem(uint256 amount) public {
        // Bound amount to reasonable values using maxDeposit
        amount = bound(amount, 1e18, stkToken.maxDeposit(user));

        // First mint some tokens to user
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Start cooldown
        stkToken.cooldown();

        // Warp to after cooldown period but within unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 totalSupply = stkToken.totalSupply();

        // Expect handleAction to be called with correct parameters
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                IRewardsController.handleAction.selector,
                user,
                totalSupply,
                amount // oldUserBalance
            )
        );

        // Perform redeem
        stkToken.redeem(amount, user, user);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 10
    function test_HandleActionOnWithdraw(uint256 amount) public {
        // Bound amount to reasonable values using maxDeposit
        amount = bound(amount, 1e18, stkToken.maxDeposit(user));

        // First mint some tokens to user
        vm.startPrank(user);
        asset.mint(user, amount);
        asset.approve(address(stkToken), amount);
        stkToken.deposit(amount, user);

        // Start cooldown
        stkToken.cooldown();

        // Warp to after cooldown period but within unstake window
        vm.warp(block.timestamp + COOLDOWN_SECONDS + 1);

        uint256 totalSupply = stkToken.totalSupply();

        // Expect handleAction to be called with correct parameters
        vm.expectCall(
            address(rewardsController),
            abi.encodeWithSelector(
                IRewardsController.handleAction.selector,
                user,
                totalSupply,
                amount // oldUserBalance
            )
        );

        // Perform withdraw
        stkToken.withdraw(amount, user, user);

        vm.stopPrank();
    }
}
