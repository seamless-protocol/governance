// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../../src/Seam.sol";
import {Constants} from "../../src/library/Constants.sol";
import {StakedToken} from "../../src/safety-module/StakedToken.sol";
import {RewardKeeper} from "../../src/safety-module/RewardKeeper.sol"; // Adjust import paths to your project structure
import {IRewardKeeper} from "../../src/interfaces/IRewardKeeper.sol";
import {RewardKeeperStorage as StorageLib} from "../../src/storage/RewardKeeperStorage.sol";
import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";
import {AaveEcosystemReserveV2} from "@aave/periphery-v3/contracts/treasury/AaveEcosystemReserveV2.sol";

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

    // Roles (same as in the contract, for convenience)
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 25298789);
        
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
                implementation.initialize.selector, address(pool), admin, address(stkSEAM), address(oracle), address(treasury)
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
            uint256 indexBefore = rewardsController.getUserRewards(assets, user, rewardTokens[k]);
            if (indexBefore > 0) {
                count++;
            }
        }
        assertEq(count, 0);

        deal(asset, user, 1000 ether);
        vm.startPrank(user);
        IERC20(asset).approve(address(stkSEAM), 1000 ether);
        stkSEAM.deposit(1000 ether, user);

        vm.warp(block.timestamp + 10);
        count = 0;
        for (uint256 i; i < rewardTokens.length; i++) {
            uint256 indexAfter = rewardsController.getUserRewards(assets, user, rewardTokens[i]);
            if (indexAfter > 0) {
                count++;
            }
        }
        // checks that there are some rewards accruing.
        assertTrue(count > 0);
    }

    function testClaim() public {

        rewardKeeper.claimAndSetRate();
        address[] memory rewardTokens = pool.getReservesList();
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
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 26 hours);
        rewardKeeper.claimAndSetRate();

        for (uint256 i = 1; i <= userCount; i++) {
            address player = address(uint160(i));
            vm.startPrank(player);
            console.log(player, 2);
            (, uint256[] memory claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0);
            }
            vm.warp(block.timestamp + 30);
            console.log(player, 3);
            (, claimedAmounts) = rewardsController.claimAllRewards(assets, player);
            for (uint256 j; j < claimedAmounts.length; j++) {
                assertTrue(claimedAmounts[j] > 0);
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
