// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StakedToken} from "../../src/safetyModule/stakedToken.sol"; // Adjust import paths to your project structure
import {StakedTokenStorage} from "../../src/storage/StakedTokenStorage.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {MockRewardsController} from "../mocks/MockRewardsController.sol";

contract StakedTokenTest is Test {
    StakedToken internal stakedToken;
    ERC20Mock underlyingAsset;
    MockRewardsController internal rewardsController;

    // Test addresses
    address internal admin = address(0xA11CE);
    address internal manager = address(0xBEEF);
    address internal pauser = address(0xDEAD);
    address internal user = address(0xCAFE);

    // Roles
    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Cooldown/Unstake config
    uint256 internal defaultCooldown = 3 days;
    uint256 internal defaultUnstakeWindow = 2 days;

    function setUp() public {
        underlyingAsset = new ERC20Mock();
        rewardsController = new MockRewardsController();

        // Deploy the StakedToken (UUPS proxy-like) directly for testing
        StakedToken implementation = new StakedToken();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                implementation.initialize.selector,
                address(underlyingAsset),
                address(rewardsController),
                admin,
                "StakedToken",
                "STK",
                defaultCooldown,
                defaultUnstakeWindow
            )
        );
        stakedToken = StakedToken(address(proxy));

        // Grant roles to manager and pauser
        vm.startPrank(admin);
        stakedToken.grantRole(MANAGER_ROLE, manager);
        stakedToken.grantRole(PAUSER_ROLE, pauser);
        stakedToken.grantRole(UPGRADER_ROLE, admin); // So admin can upgrade in tests
        vm.stopPrank();

        // Mint some tokens to user for testing
        underlyingAsset.mint(user, 10_000 ether);
        // Approve the StakedToken to spend user's tokens
        vm.prank(user);
        underlyingAsset.approve(address(stakedToken), type(uint256).max);
    }

    function testInitialization() public {
        // Basic check that initialization was correct
        assertEq(stakedToken.asset(), address(underlyingAsset), "Incorrect underlying asset");
        assertEq(stakedToken.getRewardsController(), address(rewardsController), "Incorrect rewards controller");
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
        vm.expectRevert(StakedToken.CooldownActive.selector);
        stakedToken.withdraw(1000 ether, user, user);

        // Initiate cooldown
        vm.prank(user);
        stakedToken.cooldown();
        // Advance time forward to pass the cooldown + stay within unstake window
        vm.warp(block.timestamp + defaultCooldown - 1);

        // Still in cooldown, now we can’t withdraw because it reverts if the block time hasn’t fully passed
        vm.prank(user);
        console.log(block.timestamp);
        vm.expectRevert(StakedToken.CooldownActive.selector);
        stakedToken.withdraw(1000 ether, user, user);

        // Advance into the unstake window
        vm.warp(block.timestamp + 2); // Now block.timestamp > cooldownEnd

        vm.prank(user);
        stakedToken.withdraw(1000 ether, user, user);
        assertEq(stakedToken.balanceOf(user), 0, "Withdraw didn't burn shares");
        assertEq(underlyingAsset.balanceOf(user), 10_000 ether, "User should get back underlying tokens");
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
        stakedToken.enableEmergencyWithdrawalState();

        // Pauser triggers emergency
        vm.prank(pauser);
        stakedToken.enableEmergencyWithdrawalState();

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
        stakedToken.endEmergencyWithdrawalState();

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
        stakedToken.changeController(newController);

        // Manager can change
        vm.prank(manager);
        stakedToken.changeController(newController);
        assertEq(stakedToken.getRewardsController(), newController, "Controller not updated");

        // Zero address revert
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(StakedToken.isZeroAddress.selector));
        stakedToken.changeController(address(0));
    }

    function testChangeTimers() public {
        uint256 newCooldown = 10 days;
        uint256 newUnstakeWindow = 3 days;

        // Non-manager attempt
        vm.prank(user);
        vm.expectRevert(); // user not manager
        stakedToken.changeTimers(newCooldown, newUnstakeWindow);

        vm.prank(manager);
        stakedToken.changeTimers(newCooldown, newUnstakeWindow);
        assertEq(stakedToken.getCooldown(), newCooldown, "Cooldown not updated");
        assertEq(stakedToken.getUnstakeWindow(), newUnstakeWindow, "Unstake window not updated");
    }
}
