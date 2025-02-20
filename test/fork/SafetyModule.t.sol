// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../../src/Seam.sol";
import {Constants} from "../../src/library/Constants.sol";
import {StakedToken} from "../../src/safety-module/StakedToken.sol";
import {RewardKeeper} from "../../src/safety-module/RewardKeeper.sol"; // Adjust import paths to your project structure
import {IRewardKeeper} from "../../src/interfaces/IRewardKeeper.sol";
import {ERC20TransferStrategy} from "../../src/transfer-strategies/ERC20TransferStrategy.sol";
import {RewardKeeperStorage as StorageLib} from "../../src/storage/RewardKeeperStorage.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IERC20 as ierc20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";
import {AaveEcosystemReserveV2} from "@aave/periphery-v3/contracts/treasury/AaveEcosystemReserveV2.sol";
import {IStaticATokenFactory} from "static-a-token-v3/src/interfaces/IStaticATokenFactory.sol";
import {IStaticATokenLM} from "static-a-token-v3/src/interfaces/IStaticATokenLM.sol";
import {TransparentUpgradeableProxy} from "solidity-utils/contracts/transparent-proxy/TransparentUpgradeableProxy.sol";
import {ITransparentProxyFactory} from
    "solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol";
import {StaticATokenLMHarness} from "static-a-token-v3/tests/harness/StaticATokenLMHarness.sol";
import {StaticATokenLM} from "static-a-token-v3/src/StaticATokenLM.sol";
import {StaticATokenFactory} from "static-a-token-v3/src/StaticATokenFactory.sol";

contract SeamForkTest is Test {
    Seam public SEAM = Seam(Constants.SEAM_ADDRESS);
    RewardKeeper internal rewardKeeper;
    StakedToken internal stkSEAM;

    IPool pool = IPool(Constants.POOL_ADDRESS);
    RewardsController internal rewardsController;
    IEACAggregatorProxy internal oracle = IEACAggregatorProxy(Constants.ORACLE_PLACEHOLDER);

    // Addresses
    address internal fundsAdmin = Constants.FUNDS_ADMIN;
    address internal user = address(0x1214);
    address internal admin = address(0xA11CE);
    address internal upgradeAdmin = address(0xBABE);
    AaveEcosystemReserveV2 internal treasury = AaveEcosystemReserveV2(payable(Constants.TREASURY_ADDRESS));
    address internal asset = address(Constants.SEAM_ADDRESS);
    address internal factory = address(Constants.STATIC_ATOKEN_FACTORY);
    address proxyAdmin;

    // Roles (same as in the contract, for convenience)
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 25298789);

        // for static AToken upgrade
        StaticATokenLMHarness staticATokenImplementation;
        StaticATokenFactory staticATokenFactoryImplementation;

        // deploy stkSEAM
        StakedToken imp = new StakedToken();
        ERC1967Proxy prox = new ERC1967Proxy(
            address(imp),
            abi.encodeWithSelector(
                imp.initialize.selector, address(SEAM), admin, "Staked Seam", "stkSEAM", 7 days, 1 days
            )
        );
        stkSEAM = StakedToken(address(prox));

        // deploy reward keeper
        RewardKeeper implementation = new RewardKeeper();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                implementation.initialize.selector,
                address(pool),
                admin,
                address(stkSEAM),
                address(oracle),
                address(treasury),
                factory
            )
        );
        rewardKeeper = RewardKeeper(address(proxy));

        // deploy reward controller

        rewardsController = new RewardsController(address(rewardKeeper));

        vm.prank(admin);
        rewardKeeper.setRewardsController(address(rewardsController));

        vm.prank(admin);
        stkSEAM.setController(address(rewardsController));

        vm.startPrank(fundsAdmin);

        address[] memory rewardTokens = pool.getReservesList();
        for (uint256 i; i < rewardTokens.length; i++) {
            DataTypes.ReserveData memory data = pool.getReserveData(rewardTokens[i]);
            treasury.approve(IERC20(data.aTokenAddress), address(rewardKeeper), type(uint256).max);
        }
        vm.stopPrank();

        staticATokenImplementation =
            new StaticATokenLMHarness(pool, IRewardsController(Constants.INCENTIVES_CONTROLLER_ADDRESS));
        staticATokenFactoryImplementation = new StaticATokenFactory(
            pool,
            Constants.SHORT_TIMELOCK_ADDRESS,
            ITransparentProxyFactory(Constants.TRANSPARENT_PROXY_FACTORY),
            address(staticATokenImplementation)
        );
        address[] memory tokens = IStaticATokenFactory(factory).getStaticATokens();
        vm.startPrank(Constants.SHORT_TIMELOCK_ADDRESS);
        for (uint256 i = 0; i < tokens.length; i++) {
            TransparentUpgradeableProxy(payable(tokens[i])).upgradeToAndCall(
                address(staticATokenImplementation), abi.encodeWithSelector(StaticATokenLM.initializeV2.selector)
            );
        }
        TransparentUpgradeableProxy(payable(factory)).upgradeTo(address(staticATokenFactoryImplementation));
        vm.stopPrank();
    }

    function testClaimAndSetRateSucceedsIfPeriodElapsed() public {
        vm.warp(block.timestamp + 1 days + 1);

        rewardKeeper.claimAndSetRate();

        // Check that lastClaim updated
        uint256 lastClaim = rewardKeeper.getLastClaim();
        uint256 previousPeriod = rewardKeeper.getPreviousPeriod();
        uint256 nextPeriod = (((block.timestamp / 1 days) + 1) * 1 days) - block.timestamp;
        assertEq(lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(previousPeriod, nextPeriod, "previousPeriod mismatch after claim");

        vm.warp(block.timestamp + 1 days + 30);
        uint256 nextMidnight = ((block.timestamp / 1 days) + 1) * 1 days;
        nextPeriod = nextMidnight - block.timestamp;
        rewardKeeper.claimAndSetRate();
        lastClaim = rewardKeeper.getLastClaim();
        previousPeriod = rewardKeeper.getPreviousPeriod();
        assertEq(lastClaim, block.timestamp, "lastClaim mismatch after claimAndSetRate");
        assertEq(previousPeriod, nextPeriod, "previousPeriod mismatch after claim 2");
    }

    function testHandleAction() public {
        rewardKeeper.claimAndSetRate();
        address[] memory rewardTokens = pool.getReservesList();
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);

        uint256 count;
        for (uint256 k; k < rewardTokens.length; k++) {
            address reward = IStaticATokenFactory(factory).getStaticAToken(rewardTokens[k]);
            uint256 indexBefore = rewardsController.getUserRewards(assets, user, reward);
            if (indexBefore > 0) {
                count++;
            }
        }
        assertEq(count, 0, "Count Not Zero");

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);

        vm.warp(block.timestamp + 10);
        count = 0;
        for (uint256 i; i < rewardTokens.length; i++) {
            address reward = IStaticATokenFactory(factory).getStaticAToken(rewardTokens[i]);
            uint256 indexAfter = rewardsController.getUserRewards(assets, user, reward);
            if (indexAfter > 0) {
                count++;
            }
        }
        // checks that there are some rewards accruing.
        assertTrue(count > 0, "Count Not Above Zero");
    }

    function testClaim() public {
        rewardKeeper.claimAndSetRate();
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);

        vm.warp(block.timestamp + 5 hours);
        vm.startPrank(user);
        (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, user);
        for (uint256 j; j < claimedAmounts.length; j++) {
            assertTrue(claimedAmounts[j] > 0);
        }
        vm.stopPrank();
    }

    function testClaimManyUsers(uint256 userCount) public {
        userCount = bound(userCount, 1, 100);

        rewardKeeper.claimAndSetRate();
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);

        for (uint256 k = 1; k <= userCount; k++) {
            address player = address(uint160(k));
            uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
            random = ((random % 5000) + 1) * 1e18;
            deal(asset, player, random);
            vm.startPrank(player);
            IERC20(asset).approve(address(stkSEAM), random);
            stkSEAM.deposit(random, player);
            vm.stopPrank();
            vm.warp(block.timestamp + 3);
        }

        vm.warp(block.timestamp + 2 hours);

        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            vm.startPrank(player);
            (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0);
            }
            (, claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] == 0);
            }
            vm.stopPrank();
        }
    }

    function testClaimManyUsersAndWithdraw() public {
        uint256 userCount = 2;
        vm.pauseGasMetering();
        rewardKeeper.claimAndSetRate();
        address[] memory rewardTokens = pool.getReservesList();
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);

        for (uint256 k = 1; k <= userCount; k++) {
            address player = address(uint160(k));
            uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
            random = ((random % 5000) + 1) * 1e18;
            deal(asset, player, random);
            vm.startPrank(player);
            IERC20(asset).approve(address(stkSEAM), random);
            stkSEAM.deposit(random, player);
            vm.stopPrank();
            vm.warp(block.timestamp + 3);
        }

        vm.warp(block.timestamp + 2 hours);

        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            vm.startPrank(player);
            console.log(player, 1);
            (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0);
            }
            for (uint256 j; j < rewardTokens.length; j++) {
                address aToken = pool.getReserveData(rewardTokens[j]).aTokenAddress;
                if (IERC20(aToken).balanceOf(player) > 0) {
                    try pool.withdraw(rewardTokens[j], type(uint256).max, player) {}
                    catch {
                        console.log("Failed withdraw at: ", aToken); // this is to activate treasury accrual
                    }
                }
            }
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 26 hours);
        rewardKeeper.claimAndSetRate();

        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            vm.startPrank(player);
            console.log(player, 2);
            (address[] memory rewards, uint256[] memory claimedAmounts) =
                rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0, "Claim Amount Incorrect");
            }
            vm.warp(block.timestamp + 2 hours);
            console.log(player, 3);
            (rewards, claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0, "Claim Amount Incorrect 2");
                console.log(rewards[j], " has claimed: ", claimedAmounts[j]);
            }

            for (uint256 j; j < rewardTokens.length; j++) {
                address aToken = pool.getReserveData(rewardTokens[j]).aTokenAddress;
                if (IERC20(aToken).balanceOf(player) > 0) {
                    try pool.withdraw(rewardTokens[j], type(uint256).max, player) {} // this is to activate treasury accrual
                    catch {
                        console.log("Failed withdraw at: ", aToken);
                    }
                }
            }

            vm.stopPrank();
        }
        vm.warp(block.timestamp + 26 hours);
        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            rewardKeeper.claimAndSetRate();
            vm.startPrank(player);
            stkSEAM.cooldown();

            vm.warp(block.timestamp + 7 days + 2);
            console.log(player, 4);
            stkSEAM.redeem(stkSEAM.balanceOf(player), player, player);
            (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0, "Claim Amount Incorrect 2");
            }
            vm.warp(block.timestamp + 2 hours);
            console.log(player, 5);
            (, claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] == 0);
            }

            for (uint256 j; j < rewardTokens.length; j++) {
                address aToken = pool.getReserveData(rewardTokens[j]).aTokenAddress;
                if (IERC20(aToken).balanceOf(player) > 0) {
                    try pool.withdraw(rewardTokens[j], type(uint256).max, player) {}
                    catch {
                        console.log("Failed withdraw at: ", aToken); // this is to activate treasury accrual
                    }
                }
            }
        }
    }

    function testClaimLMRewards() public {
        rewardKeeper.claimAndSetRate();
        address[] memory rewardTokens = pool.getReservesList();
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);

        vm.warp(block.timestamp + 35 hours);
        vm.startPrank(user);
        (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, user);
        for (uint256 j; j < claimedAmounts.length; j++) {
            assertTrue(claimedAmounts[j] > 0);
        }
        vm.stopPrank();
        vm.prank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        uint256 timesSuccessful;
        for (uint256 i; i < rewardTokens.length; i++) {
            address staticAToken = IStaticATokenFactory(factory).getStaticAToken(rewardTokens[i]);
            if (staticAToken == address(0)) {
                continue; // 0x9660Af3B1955648A72F5C958E80449032d645755
            }
            address[] memory rewards = IStaticATokenLM(staticAToken).rewardTokens();
            address[] memory rewardArray = new address[](1);

            for (uint256 k; k < rewards.length; k++) {
                rewardArray[0] = rewards[k];
                (bool success,) = address(rewardKeeper).call(
                    abi.encodeWithSelector(
                        rewardKeeper.claimLMRewards.selector, address(this), rewardTokens[i], rewardArray
                    )
                );

                if (success) {
                    // If it didn't revert, increment our success counter
                    timesSuccessful++;
                }
            }
            assertTrue(timesSuccessful > 0, "Not successful");
        }
    }

    function testClaimLMRewardsRevertsWithWrongArray() public {
        rewardKeeper.claimAndSetRate();
        address[] memory rewardTokens = pool.getReservesList();
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);

        vm.warp(block.timestamp + 35 hours);
        vm.startPrank(user);
        (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, user);
        for (uint256 j; j < claimedAmounts.length; j++) {
            assertTrue(claimedAmounts[j] > 0);
        }
        vm.stopPrank();
        vm.prank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        address[] memory rewardArray = new address[](1);
        rewardArray[0] = address(1);
        vm.expectRevert();
        rewardKeeper.claimLMRewards(address(this), rewardTokens[0], rewardArray);
    }

    function testClaimLMRewardsRevertsWithNoTransferStrategy() public {
        address[] memory rewardTokens = pool.getReservesList();
        address[] memory rewardArray = new address[](1);
        rewardArray[0] = address(1);
        vm.prank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.TransferStrategyNotSet.selector));
        rewardKeeper.claimLMRewards(address(this), rewardTokens[0], rewardArray);
    }

    // test manual rates
    function testSetTokenForManualRates() public {
        address SEAMAddr = Constants.SEAM_ADDRESS;
        vm.prank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.ZeroAddress.selector, address(0)));
        rewardKeeper.setTokenForManualRate(address(0), true);

        rewardKeeper.setTokenForManualRate(SEAMAddr, true);
        bool status = rewardKeeper.getIsAllowedForManualRate(SEAMAddr);
        assertTrue(status, "Wrong assignment");
        rewardKeeper.setTokenForManualRate(SEAMAddr, false);
        status = rewardKeeper.getIsAllowedForManualRate(SEAMAddr);
        assertTrue(!status, "Wrong removal");
    }

    function testSetManualRateUnauthorizedToken() public {
        vm.startPrank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        rewardKeeper.grantRole(keccak256("REWARD_SETTER_ROLE"), address(this));
        vm.stopPrank();

        address[] memory rewardTokens = new address[](1);
        uint88[] memory rates = new uint88[](1);
        rewardTokens[0] = address(2);
        rates[0] = 5;

        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.SetManualRateNotAuthorized.selector));
        rewardKeeper.setManualRate(rewardTokens, rates);

        rewardTokens[0] = address(0);

        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.SetManualRateNotAuthorized.selector));
        rewardKeeper.setManualRate(rewardTokens, rates);
    }

    function testSetManualRateWorksWithZero() public {
        vm.startPrank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        rewardKeeper.grantRole(keccak256("REWARD_SETTER_ROLE"), address(this));
        vm.stopPrank();
        address SEAMAddr = Constants.SEAM_ADDRESS;
        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(ierc20(address(SEAMAddr)), address(rewardsController), address(rewardKeeper));
        address[] memory rewardTokens = new address[](1);
        uint88[] memory rates = new uint88[](1);
        rewardTokens[0] = SEAMAddr;
        rates[0] = 0;
        rewardKeeper.setTokenForManualRate(SEAMAddr, true);

        // revert without error, due to no configureAsset called
        vm.expectRevert();
        rewardKeeper.setManualRate(rewardTokens, rates);

        rewardKeeper.configureAsset(SEAMAddr, 0, 0, address(transferStrategy), address(oracle));

        rewardKeeper.setManualRate(rewardTokens, rates);
    }

    function testSetConfigureAssetsInvalidToken() public {
        vm.startPrank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        rewardKeeper.grantRole(keccak256("REWARD_SETTER_ROLE"), address(this));
        vm.stopPrank();
        address SEAMAddr = Constants.SEAM_ADDRESS;

        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(ierc20(address(SEAMAddr)), address(rewardsController), address(rewardKeeper));

        vm.expectRevert(abi.encodeWithSelector(IRewardKeeper.SetManualRateNotAuthorized.selector));
        rewardKeeper.configureAsset(SEAMAddr, 0, 0, address(transferStrategy), address(oracle));
    }

    function testSetManualRate() public {
        rewardKeeper.claimAndSetRate();
        vm.startPrank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        rewardKeeper.grantRole(keccak256("REWARD_SETTER_ROLE"), address(this));
        vm.stopPrank();
        address SEAMAddr = Constants.SEAM_ADDRESS;

        rewardKeeper.setTokenForManualRate(SEAMAddr, true);
        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(ierc20(address(SEAMAddr)), address(rewardsController), address(rewardKeeper));
        rewardKeeper.configureAsset(SEAMAddr, 0, 0, address(transferStrategy), address(oracle));

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);
        vm.stopPrank();
        vm.warp(block.timestamp + 10);

        deal(SEAMAddr, address(this), 500 ether);
        uint256 time = block.timestamp + 7 days;
        uint256 rate = uint256(500 ether / time);
        IERC20(SEAMAddr).approve(address(rewardKeeper), rate * time);

        address[] memory rewardTokens = new address[](1);
        uint88[] memory rates = new uint88[](1);
        rewardTokens[0] = SEAMAddr;
        rates[0] = uint88(rate);

        rewardKeeper.setManualRate(rewardTokens, rates);
        rewardKeeper.setManualDistributionEnd(SEAMAddr, uint32(time));
        address transferStrat = rewardsController.getTransferStrategy(SEAMAddr);
        assertTrue(transferStrat != address(0), "Transfer Strategy Not Deployed");

        uint256 balTStrat = IERC20(SEAMAddr).balanceOf(transferStrat);
        assertTrue(balTStrat == 0, "Wrong balance");

        uint256 distributionEnd = rewardsController.getDistributionEnd(address(stkSEAM), SEAMAddr);
        assertEq(distributionEnd, time, "Wrong distribution end");
    }

    function testSetManualRateCorrectlyEmits() public {
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);
        rewardKeeper.claimAndSetRate();
        vm.startPrank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        rewardKeeper.grantRole(keccak256("REWARD_SETTER_ROLE"), address(this));
        vm.stopPrank();
        address SEAMAddr = Constants.SEAM_ADDRESS;

        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(ierc20(address(SEAMAddr)), address(rewardsController), address(rewardKeeper));

        rewardKeeper.setTokenForManualRate(SEAMAddr, true);
        rewardKeeper.configureAsset(SEAMAddr, 0, 0, address(transferStrategy), address(oracle));

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);
        vm.stopPrank();
        vm.warp(block.timestamp + 10);

        deal(SEAMAddr, address(this), 500 ether);
        uint256 time = 7 days;
        uint256 rate = uint256(500 ether / time);
        IERC20(SEAMAddr).transfer(address(transferStrategy), rate * time);
        address[] memory rewardTokens = new address[](1);
        uint88[] memory rates = new uint88[](1);
        rewardTokens[0] = SEAMAddr;
        rates[0] = uint88(rate);
        rewardKeeper.setManualRate(rewardTokens, rates);
        rewardKeeper.setManualDistributionEnd(SEAMAddr, uint32(block.timestamp + time));

        vm.warp(block.timestamp + 8 days);
        uint256 balBefore = IERC20(SEAMAddr).balanceOf(user);
        vm.prank(user);
        rewardsController.claimAllRewards(assets, user);
        uint256 balAfter = IERC20(SEAMAddr).balanceOf(user);
        assertEq(balAfter, balBefore + (rate * time), "Wrong reward distribution");
    }

    function testSetManualRateFromConfigureAssets() public {
        address[] memory assets = new address[](1);
        assets[0] = address(stkSEAM);
        rewardKeeper.claimAndSetRate();
        vm.startPrank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        rewardKeeper.grantRole(keccak256("REWARD_SETTER_ROLE"), address(this));
        vm.stopPrank();
        address SEAMAddr = Constants.SEAM_ADDRESS;

        rewardKeeper.setTokenForManualRate(SEAMAddr, true);

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);
        vm.stopPrank();
        vm.warp(block.timestamp + 10);

        deal(SEAMAddr, address(this), 500 ether);
        uint256 time = 7 days;
        uint256 rate = uint256(500 ether / time);

        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(ierc20(address(SEAMAddr)), address(rewardsController), address(rewardKeeper));
        IERC20(SEAMAddr).transfer(address(transferStrategy), rate * time);
        rewardKeeper.configureAsset(
            SEAMAddr, uint88(rate), uint32(time + block.timestamp), address(transferStrategy), address(oracle)
        );

        vm.warp(block.timestamp + 8 days);
        uint256 balBefore = IERC20(SEAMAddr).balanceOf(user);
        vm.prank(user);
        rewardsController.claimAllRewards(assets, user);
        uint256 balAfter = IERC20(SEAMAddr).balanceOf(user);
        assertEq(balAfter, balBefore + (rate * time), "Wrong reward distribution");
    }

    function testSetTransferStrategy() public {
        vm.startPrank(admin);
        rewardKeeper.grantRole(keccak256("MANAGER_ROLE"), address(this));
        rewardKeeper.grantRole(keccak256("REWARD_SETTER_ROLE"), address(this));
        vm.stopPrank();
        address SEAMAddr = Constants.SEAM_ADDRESS;

        rewardKeeper.setTokenForManualRate(SEAMAddr, true);

        ERC20TransferStrategy transferStrategy =
            new ERC20TransferStrategy(ierc20(address(SEAMAddr)), address(rewardsController), address(rewardKeeper));

        rewardKeeper.configureAsset(SEAMAddr, 0, 0, address(transferStrategy), address(oracle));
        rewardKeeper.setTransferStrategy(SEAMAddr, address(rewardKeeper));

        address transferStrat = rewardsController.getTransferStrategy(SEAMAddr);
        assertEq(transferStrat, address(rewardKeeper));
    }

    function testReturnStaticATokenFactory() public view {
        IStaticATokenFactory tokenFactory = rewardKeeper.getStaticATokenFactory();
        assertEq(address(tokenFactory), factory);
    }

    function testGetTreasury() public view {
        address treasure = rewardKeeper.getTreasury();
        assertEq(treasure, address(treasury));
    }
}
