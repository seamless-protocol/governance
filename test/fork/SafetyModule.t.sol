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
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {RewardsDataTypes} from "@aave/periphery-v3/contracts/rewards/libraries/RewardsDataTypes.sol";
import {RewardsController} from "@aave/periphery-v3/contracts/rewards/RewardsController.sol";

contract SeamForkTest is Test {
    Seam public SEAM = Seam(Constants.SEAM_ADDRESS);
    RewardKeeper internal rewardKeeper;
    StakedToken internal stkSEAM;

    IPool mockPool = IPool(vm.envAddress("POOL"));
    RewardsController internal rewardsController;
    IEACAggregatorProxy internal oracle = IEACAggregatorProxy(vm.envAddress("ORACLE"));

    // Addresses
    address internal admin = address(0xA11CE);
    address internal upgradeAdmin = address(0xBABE);
    address internal treasury = address(vm.envAddress("TREASURY"));

    // Roles (same as in the contract, for convenience)
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 25298789);
        
        // deploy stkSEAM
        StakedToken Imp = new StakedToken();
        ERC1967Proxy prox = new ERC1967Proxy(
            address(Imp),
            abi.encodeWithSelector(
                Imp.initialize.selector, address(SEAM), admin, "Staked Seam", "stkSEAM", 7 days, 1 days
            )
        );
        stkSEAM = StakedToken(address(prox));
        
        // deploy reward keeper
        RewardKeeper implementation = new RewardKeeper();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                implementation.initialize.selector, address(mockPool), admin, address(stkSEAM), address(oracle), treasury
            )
        );
        rewardKeeper = RewardKeeper(address(proxy));
        
        // deploy reward controller
        rewardsController = new RewardsController(address(rewardKeeper));
        
        vm.prank(admin);
        rewardKeeper.setRewardsController(address(rewardsController));
        
        vm.prank(admin);
        stkSEAM.setController(address(rewardsController));
        
        vm.startPrank(treasury);
        
        address[] memory rewardTokens = mockPool.getReservesList();
        for (uint256 i; i < rewardTokens.length; i++) {
            DataTypes.ReserveData memory data = mockPool.getReserveData(rewardTokens[i]);
            IERC20 aToken = IERC20(data.aTokenAddress);
            aToken.approve(address(rewardKeeper), type(uint256).max);
        }

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

    
}
