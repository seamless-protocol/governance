// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ITransferStrategyBase} from "src/interfaces/ITransferStrategyBase.sol";
import {SeamTransferStrategy} from "src/transfer-strategies/SeamTransferStrategy.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";

contract SeamTransferStrategyTest is Test {
    address immutable incentivesController = makeAddr("incentivesController");
    address immutable rewardsAdmin = makeAddr("rewardsAdmin");
    address immutable escrowSeam = makeAddr("escrowSeam");
    ERC20Mock immutable seam = new ERC20Mock();

    SeamTransferStrategy strategy;

    function setUp() public {
        strategy = new SeamTransferStrategy(IERC20(seam), incentivesController, rewardsAdmin);
    }

    function test_SetUp() public {
        assertEq(strategy.getIncentivesController(), incentivesController);
        assertEq(strategy.getRewardsAdmin(), rewardsAdmin);
        assertEq(address(strategy.seam()), address(seam));
    }

    function testFuzz_PerformTransfer(address user, uint256 amount) public {
        vm.assume(user != address(0));

        deal(address(seam), address(strategy), type(uint256).max);
        vm.expectCall(address(seam), abi.encodeWithSelector(IERC20.transfer.selector, user, amount));
        vm.startPrank(incentivesController);
        strategy.performTransfer(user, address(0), amount);
        vm.stopPrank();
    }

    function testFuzz_PerformTransfer_RevertIf_NotIncentivesController(address caller, address user, uint256 amount)
        public
    {
        vm.assume(caller != incentivesController);
        vm.startPrank(caller);
        vm.expectRevert(ITransferStrategyBase.NotIncentivesController.selector);
        strategy.performTransfer(user, address(0), amount);
        vm.stopPrank();
    }

    function testFuzz_EmergencyTransfer(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(strategy));

        uint256 strategyBalanceBefore = type(uint256).max;
        deal(address(seam), address(strategy), strategyBalanceBefore);
        vm.startPrank(rewardsAdmin);
        strategy.emergencyWithdrawal(address(seam), to, amount);
        vm.stopPrank();

        assertEq(seam.balanceOf(to), amount);
        assertEq(seam.balanceOf(address(strategy)), strategyBalanceBefore - amount);
    }

    function testFuzz_EmergencyTransfer_RevertIf_NotRewardsAdmin(address caller, address to, uint256 amount) public {
        vm.assume(caller != rewardsAdmin);
        vm.startPrank(caller);
        vm.expectRevert(ITransferStrategyBase.NotRewardsAdmin.selector);
        strategy.emergencyWithdrawal(address(seam), to, amount);
        vm.stopPrank();
    }
}
