// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../../src/Seam.sol";
import {Constants} from "../../src/library/Constants.sol";
import {IMetaMorphoV1_1} from "../../src/interfaces/IMetaMorphoV1_1.sol";
import {ERC20BalanceSplitterTwoPayee} from "../../src/ERC20BalanceSplitterTwoPayee.sol";
import {SeamStakingScript} from "../../script/SeamStaking.s.sol";
import {FeeKeeper} from "../../src/FeeKeeper.sol";
import {RewardsController} from "aave-v3-periphery/contracts/rewards/RewardsController.sol";
import {StakedToken} from "../../src/StakedToken.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract SeamStakingTest is Test, SeamStakingScript {
    Seam constant SEAM = Seam(Constants.SEAM_ADDRESS);

    IMetaMorphoV1_1 constant SEAMLESS_USDC_VAULT = IMetaMorphoV1_1(Constants.SEAMLESS_USDC_VAULT);
    IMetaMorphoV1_1 constant SEAMLESS_CBBTC_VAULT = IMetaMorphoV1_1(Constants.SEAMLESS_CBBTC_VAULT);
    IMetaMorphoV1_1 constant SEAMLESS_WETH_VAULT = IMetaMorphoV1_1(Constants.SEAMLESS_WETH_VAULT);

    StakedToken stkToken;
    FeeKeeper feeKeeper;
    RewardsController rewardsController;

    ERC20BalanceSplitterTwoPayee usdcSplitter;
    ERC20BalanceSplitterTwoPayee cbbtcSplitter;
    ERC20BalanceSplitterTwoPayee wethSplitter;

    address deployer;

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 27297886);

        deployer = makeAddr("deployer");

        vm.startPrank(deployer);

        (feeKeeper, stkToken, rewardsController) = SeamStakingScript._deployStakedTokenAndDependencies(deployer);

        (usdcSplitter, cbbtcSplitter, wethSplitter) = SeamStakingScript._deployFeeSplitters(feeKeeper);

        SeamStakingScript._assignRolesToGovernance(stkToken, feeKeeper, deployer);

        vm.stopPrank();

        vm.prank(SEAMLESS_USDC_VAULT.owner());
        SEAMLESS_USDC_VAULT.setFeeRecipient(address(usdcSplitter));

        vm.prank(SEAMLESS_CBBTC_VAULT.owner());
        SEAMLESS_CBBTC_VAULT.setFeeRecipient(address(cbbtcSplitter));

        vm.prank(SEAMLESS_WETH_VAULT.owner());
        SEAMLESS_WETH_VAULT.setFeeRecipient(address(wethSplitter));
    }

    function test_SetupValidation() public {
        // Validate StakedToken setup
        assertEq(stkToken.name(), "Staked SEAM");
        assertEq(stkToken.symbol(), "stkSEAM");
        assertEq(stkToken.getCooldown(), 7 days);
        assertEq(stkToken.getUnstakeWindow(), 1 days);
        assertEq(stkToken.asset(), Constants.SEAM_ADDRESS);
        assertEq(address(stkToken.getRewardsController()), address(rewardsController));

        // Validate FeeKeeper setup
        assertEq(feeKeeper.getAsset(), address(stkToken));
        assertEq(address(feeKeeper.getController()), address(rewardsController));
        assertEq(address(feeKeeper.getOracle()), address(Constants.ORACLE_PLACEHOLDER));

        // Validate roles on StakedToken
        assertTrue(stkToken.hasRole(stkToken.DEFAULT_ADMIN_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(stkToken.hasRole(stkToken.MANAGER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(stkToken.hasRole(stkToken.UPGRADER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(stkToken.hasRole(stkToken.PAUSER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(stkToken.hasRole(stkToken.PAUSER_ROLE(), Constants.GUARDIAN_WALLET));

        // Validate roles on FeeKeeper
        assertTrue(feeKeeper.hasRole(feeKeeper.DEFAULT_ADMIN_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(feeKeeper.hasRole(feeKeeper.MANAGER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(feeKeeper.hasRole(feeKeeper.UPGRADER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(feeKeeper.hasRole(feeKeeper.PAUSER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(feeKeeper.hasRole(feeKeeper.REWARD_SETTER_ROLE(), Constants.SHORT_TIMELOCK_ADDRESS));
        assertTrue(feeKeeper.hasRole(feeKeeper.REWARD_SETTER_ROLE(), Constants.GUARDIAN_WALLET));
        assertTrue(feeKeeper.hasRole(feeKeeper.PAUSER_ROLE(), Constants.GUARDIAN_WALLET));

        // Check that deployer does not have any roles
        assertFalse(stkToken.hasRole(stkToken.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(stkToken.hasRole(stkToken.MANAGER_ROLE(), deployer));
        assertFalse(stkToken.hasRole(stkToken.UPGRADER_ROLE(), deployer));
        assertFalse(stkToken.hasRole(stkToken.PAUSER_ROLE(), deployer));

        assertFalse(feeKeeper.hasRole(feeKeeper.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(feeKeeper.hasRole(feeKeeper.MANAGER_ROLE(), deployer));
        assertFalse(feeKeeper.hasRole(feeKeeper.UPGRADER_ROLE(), deployer));
        assertFalse(feeKeeper.hasRole(feeKeeper.PAUSER_ROLE(), deployer));
        assertFalse(feeKeeper.hasRole(feeKeeper.REWARD_SETTER_ROLE(), deployer));

        // Validate fee splitters setup
        // Check USDC splitter
        assertEq(usdcSplitter.payeeA(), address(feeKeeper));
        assertEq(usdcSplitter.payeeB(), Constants.CURATOR_FEE_RECIPIENT);
        assertEq(usdcSplitter.shareA(), 6000);
        assertEq(address(usdcSplitter.token()), Constants.SEAMLESS_USDC_VAULT);

        // Check cbBTC splitter
        assertEq(cbbtcSplitter.payeeA(), address(feeKeeper));
        assertEq(cbbtcSplitter.payeeB(), Constants.CURATOR_FEE_RECIPIENT);
        assertEq(cbbtcSplitter.shareA(), 6000);
        assertEq(address(cbbtcSplitter.token()), Constants.SEAMLESS_CBBTC_VAULT);

        // Check WETH splitter
        assertEq(wethSplitter.payeeA(), address(feeKeeper));
        assertEq(wethSplitter.payeeB(), Constants.CURATOR_FEE_RECIPIENT);
        assertEq(wethSplitter.shareA(), 6000);
        assertEq(address(wethSplitter.token()), Constants.SEAMLESS_WETH_VAULT);

        // Validate fee sources are registered in FeeKeeper using getFeeSources()
        address[] memory feeSources = feeKeeper.getFeeSources();
        assertEq(feeSources.length, 3);
        assertTrue(contains(feeSources, address(usdcSplitter)));
        assertTrue(contains(feeSources, address(cbbtcSplitter)));
        assertTrue(contains(feeSources, address(wethSplitter)));
    }

    function testFuzz_EndToEnd(uint256 amount1, uint256 amount2, uint256 timeWarp) public {
        timeWarp = bound(timeWarp, 1 days, 30 days);

        // Get the max deposit amount from the staked token contract
        // Need to reduce maxDeposit or RewardsController index will round to 0. SEAM totalSupply is 100,000,000 so this is safe
        uint256 maxDeposit = 100_000_000e18;

        amount1 = bound(amount1, 1, maxDeposit - 1);
        amount2 = bound(amount2, 1, maxDeposit - amount1);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // Give users enough tokens for their deposits
        deal(address(SEAM), user1, amount1);
        deal(address(SEAM), user2, amount2);

        _performDeposits(user1, user2, amount1, amount2);

        // Warp forward 1 day to accrue fees on vaults
        vm.warp(block.timestamp + timeWarp);

        _forceInterestAccrual();

        // Get splitter balances
        (uint256 usdcSplitterBalance, uint256 cbbtcSplitterBalance, uint256 wethSplitterBalance) =
            _getSplitterBalances();

        // Store the curator's balances before force accrual
        (
            uint256 curatorUsdcVaultBalanceBefore,
            uint256 curatorCbbtcVaultBalanceBefore,
            uint256 curatorWethVaultBalanceBefore
        ) = _getCuratorBalances();

        // Trigger claim to distribute the fees
        feeKeeper.claimAndSetRate();

        // Check curator fee balances after accrual
        (
            uint256 curatorUsdcVaultBalanceAfter,
            uint256 curatorCbbtcVaultBalanceAfter,
            uint256 curatorWethVaultBalanceAfter
        ) = _getCuratorBalances();

        // Verify curator received fees
        // Verify curator received exactly 40% of total fees (60/40 split with 6000 basis points to FeeKeeper)
        assertEq(curatorUsdcVaultBalanceAfter - curatorUsdcVaultBalanceBefore, usdcSplitterBalance * 4000 / 10000);
        assertEq(curatorCbbtcVaultBalanceAfter - curatorCbbtcVaultBalanceBefore, cbbtcSplitterBalance * 4000 / 10000);
        assertEq(curatorWethVaultBalanceAfter - curatorWethVaultBalanceBefore, wethSplitterBalance * 4000 / 10000);

        // Check that RewardsController emission rates and distribution end are set correctly
        _verifyRewardsDistribution(
            SEAMLESS_USDC_VAULT, curatorUsdcVaultBalanceAfter - curatorUsdcVaultBalanceBefore, usdcSplitterBalance
        );
        _verifyRewardsDistribution(
            SEAMLESS_CBBTC_VAULT, curatorCbbtcVaultBalanceAfter - curatorCbbtcVaultBalanceBefore, cbbtcSplitterBalance
        );
        _verifyRewardsDistribution(
            SEAMLESS_WETH_VAULT, curatorWethVaultBalanceAfter - curatorWethVaultBalanceBefore, wethSplitterBalance
        );

        vm.warp(block.timestamp + 2 days);

        _claimRewards(user1, user2);

        _verifyUserRewards(
            user1,
            user2,
            usdcSplitterBalance,
            cbbtcSplitterBalance,
            wethSplitterBalance,
            curatorUsdcVaultBalanceAfter - curatorUsdcVaultBalanceBefore,
            curatorCbbtcVaultBalanceAfter - curatorCbbtcVaultBalanceBefore,
            curatorWethVaultBalanceAfter - curatorWethVaultBalanceBefore
        );
    }

    function _performDeposits(address user1, address user2, uint256 amount1, uint256 amount2) internal {
        // User 1 deposits
        vm.startPrank(user1);
        SEAM.approve(address(stkToken), amount1);
        stkToken.deposit(amount1, user1);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        SEAM.approve(address(stkToken), amount2);
        stkToken.deposit(amount2, user2);
        vm.stopPrank();

        // Verify balances
        assertEq(stkToken.balanceOf(user1), amount1);
        assertEq(stkToken.balanceOf(user2), amount2);
    }

    function _getSplitterBalances() internal view returns (uint256, uint256, uint256) {
        uint256 usdcSplitterBalance = SEAMLESS_USDC_VAULT.balanceOf(address(usdcSplitter));
        uint256 cbbtcSplitterBalance = SEAMLESS_CBBTC_VAULT.balanceOf(address(cbbtcSplitter));
        uint256 wethSplitterBalance = SEAMLESS_WETH_VAULT.balanceOf(address(wethSplitter));

        // Check that fee splitters have non-zero balances
        assertTrue(usdcSplitterBalance > 0);
        assertTrue(cbbtcSplitterBalance > 0);
        assertTrue(wethSplitterBalance > 0);

        return (usdcSplitterBalance, cbbtcSplitterBalance, wethSplitterBalance);
    }

    function _getCuratorBalances() internal view returns (uint256, uint256, uint256) {
        return (
            SEAMLESS_USDC_VAULT.balanceOf(Constants.CURATOR_FEE_RECIPIENT),
            SEAMLESS_CBBTC_VAULT.balanceOf(Constants.CURATOR_FEE_RECIPIENT),
            SEAMLESS_WETH_VAULT.balanceOf(Constants.CURATOR_FEE_RECIPIENT)
        );
    }

    function _claimRewards(address user1, address user2) internal {
        address[] memory assets = new address[](1);
        assets[0] = address(stkToken);

        vm.prank(user1);
        rewardsController.claimAllRewardsToSelf(assets);

        vm.prank(user2);
        rewardsController.claimAllRewardsToSelf(assets);
    }

    function _verifyUserRewards(
        address user1,
        address user2,
        uint256 usdcSplitterBalance,
        uint256 cbbtcSplitterBalance,
        uint256 wethSplitterBalance,
        uint256 curatorUsdcFee,
        uint256 curatorCbbtcFee,
        uint256 curatorWethFee
    ) internal view {
        // Verify users received rewards proportional to their staked SEAM
        _verifyUserRewardsForToken(user1, user2, usdcSplitterBalance, curatorUsdcFee, SEAMLESS_USDC_VAULT);

        _verifyUserRewardsForToken(user1, user2, cbbtcSplitterBalance, curatorCbbtcFee, SEAMLESS_CBBTC_VAULT);

        _verifyUserRewardsForToken(user1, user2, wethSplitterBalance, curatorWethFee, SEAMLESS_WETH_VAULT);
    }

    function _verifyUserRewardsForToken(
        address user1,
        address user2,
        uint256 splitterBalance,
        uint256 curatorFee,
        IMetaMorphoV1_1 vault
    ) internal view {
        // Calculate total rewards (splitter balance minus curator fee)
        uint256 period = feeKeeper.getPreviousPeriod();
        uint256 totalRewards = (splitterBalance - curatorFee) / period;
        totalRewards = totalRewards * period;

        // Each user may lose up to 1 wei due to rounding on the RewardsController, so when add them together that makes a max difference of 2 wei
        assertApproxEqAbs(vault.balanceOf(user1) + vault.balanceOf(user2), totalRewards, 2);
        assertLe(vault.balanceOf(user1) + vault.balanceOf(user2), totalRewards);
    }

    function _verifyRewardsDistribution(IMetaMorphoV1_1 token, uint256 curatorFeeBalance, uint256 feeSplitterBalance)
        internal
    {
        // Get emission data from RewardsController
        (, uint256 emissionPerSecond,, uint256 distributionEnd) =
            rewardsController.getRewardsData(address(stkToken), address(token));

        // Get transfer strategy address
        address transferStrategy = rewardsController.getTransferStrategy(address(token));

        // Get token balance in transfer strategy
        uint256 transferStrategyBalance = token.balanceOf(transferStrategy);

        uint256 period = feeKeeper.getPreviousPeriod();

        // Calculate expected emission rate (tokens per second)
        uint256 expectedEmissionRate = (feeSplitterBalance - curatorFeeBalance) / period;

        // Verify exact emission rate
        assertEq(emissionPerSecond, expectedEmissionRate);

        // Verify exact distribution end time
        assertEq(distributionEnd, block.timestamp + period);

        // Verify transfer strategy is deployed with exact address
        assertTrue(transferStrategy != address(0));

        // Verify transfer strategy has exactly the right amount of tokens
        assertEq(transferStrategyBalance, expectedEmissionRate * period);
    }

    function _forceInterestAccrual() internal {
        // Deposit 1 wei into each vault to force interest to accrue
        address depositor = makeAddr("depositor");

        // Fund the depositor with tokens for each vault
        deal(Constants.USDC, depositor, 1);
        deal(Constants.CBBTC, depositor, 1);
        deal(Constants.WETH, depositor, 1);

        vm.startPrank(depositor);

        // Approve and deposit into USDC vault
        IERC20(Constants.USDC).approve(address(SEAMLESS_USDC_VAULT), 1);
        SEAMLESS_USDC_VAULT.deposit(1, depositor);

        // Approve and deposit into cbBTC vault
        IERC20(Constants.CBBTC).approve(address(SEAMLESS_CBBTC_VAULT), 1);
        SEAMLESS_CBBTC_VAULT.deposit(1, depositor);

        // Approve and deposit into WETH vault
        IERC20(Constants.WETH).approve(address(SEAMLESS_WETH_VAULT), 1);
        SEAMLESS_WETH_VAULT.deposit(1, depositor);

        vm.stopPrank();
    }

    // Helper function to check if an array contains a specific address
    function contains(address[] memory addresses, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == target) {
                return true;
            }
        }
        return false;
    }
}
