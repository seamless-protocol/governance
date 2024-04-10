// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IEscrowSeam} from "src/interfaces/IEscrowSeam.sol";
import {ITransferStrategyBase} from "src/interfaces/ITransferStrategyBase.sol";
import {EscrowSeamTransferStrategy} from "src/transfer-strategies/EscrowSeamTransferStrategy.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";

contract EscrowSeamTransferStrategyTest is Test {
    address immutable incentivesController = makeAddr("incentivesController");
    address immutable rewardsAdmin = makeAddr("rewardsAdmin");
    address immutable escrowSeam = makeAddr("escrowSeam");
    ERC20Mock immutable seam = new ERC20Mock();

    EscrowSeamTransferStrategy strategy;

    function setUp() public {
        strategy =
            new EscrowSeamTransferStrategy(IERC20(seam), IEscrowSeam(escrowSeam), incentivesController, rewardsAdmin);
    }

    function test_SetUp() public {
        assertEq(strategy.getIncentivesController(), incentivesController);
        assertEq(strategy.getRewardsAdmin(), rewardsAdmin);
        assertEq(address(strategy.seam()), address(seam));
        assertEq(address(strategy.escrowSeam()), escrowSeam);
    }

    function testFuzz_PerformTransfer(address user, uint256 amount) public {
        vm.assume(user != address(0));

        deal(address(seam), address(strategy), type(uint256).max);
        vm.mockCall(
            address(escrowSeam), abi.encodeWithSelector(IEscrowSeam.deposit.selector, user, amount), abi.encode()
        );
        vm.expectCall(address(escrowSeam), abi.encodeWithSelector(IEscrowSeam.deposit.selector, user, amount));
        vm.startPrank(incentivesController);
        strategy.performTransfer(user, address(0), amount);
        vm.stopPrank();
    }

    function testFuzz_PerformTransfer_RevertIf_NotIncentivesController(address caller, address user, uint256 amount)
        public
    {
        vm.assume(caller != incentivesController);
        vm.startPrank(user);
        vm.expectRevert(ITransferStrategyBase.NotIncentivesController.selector);
        strategy.performTransfer(user, address(0), amount);
        vm.stopPrank();
    }

    function testFuzz_EmergencyTransfer(address to, uint256 amount) public {
        vm.assume(to != address(0));

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
