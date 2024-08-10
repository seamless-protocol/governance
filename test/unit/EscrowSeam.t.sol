// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EscrowSeam} from "src/EscrowSeam.sol";
import {IEscrowSeam} from "src/interfaces/IEscrowSeam.sol";

contract EscrowSeamTest is Test {
    uint256 public constant REL_ROUNDING_TOLERANCE = 0.0001 ether;
    uint256 public constant ABS_ROUNDING_TOLERANCE = 10;
    uint256 public constant VESTING_DURATION = 365 days;
    address public immutable seam = makeAddr("seam");

    EscrowSeam public esSEAM;

    function setUp() public {
        EscrowSeam implementation = new EscrowSeam();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(EscrowSeam.initialize.selector, address(seam), VESTING_DURATION, address(this))
        );
        esSEAM = EscrowSeam(address(proxy));
    }

    function testDeploy() public {
        assertEq(address(esSEAM.seam()), seam);
        assertEq(esSEAM.vestingDuration(), VESTING_DURATION);
        assertEq(esSEAM.owner(), address(this));
        assertEq(esSEAM.clock(), block.timestamp);
        assertEq(esSEAM.CLOCK_MODE(), "mode=timestamp");
    }

    function testFuzzTransferRevertNonTransferable(address from, address to, uint256 amount) public {
        vm.expectRevert(IEscrowSeam.NonTransferable.selector);

        vm.startPrank(from);
        esSEAM.transfer(to, amount);
        vm.stopPrank();
    }

    function testFuzzTransferFromRevertNonTransferable(address from, address to, uint256 amount) public {
        vm.expectRevert(IEscrowSeam.NonTransferable.selector);
        esSEAM.transferFrom(from, to, amount);
    }

    function testSimpleDeposit() public {
        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

        address account = makeAddr("account");
        uint256 depositAmount = 1000 ether;
        esSEAM.deposit(account, depositAmount);

        (uint256 claimableAmount, uint256 decreasePerSecond, uint256 vestingEndsAt, uint256 lastUpdatedTimestamp) =
            esSEAM.vestingInfo(account);
        assertEq(claimableAmount, 0);
        assertEq(decreasePerSecond, (depositAmount * 1 ether) / VESTING_DURATION);
        assertEq(vestingEndsAt, block.timestamp + VESTING_DURATION);
        assertEq(lastUpdatedTimestamp, block.timestamp);
    }

    function testFuzzSimpleDeposit(address account, uint256 depositAmount) public {
        vm.assume(account != address(0));
        depositAmount = bound(depositAmount, 1, type(uint256).max / 1 ether);
        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

        esSEAM.deposit(account, depositAmount);

        (uint256 claimableAmount, uint256 decreasePerSecond, uint256 vestingEndsAt, uint256 lastUpdatedTimestamp) =
            esSEAM.vestingInfo(account);
        assertEq(claimableAmount, 0);
        assertEq(decreasePerSecond, (depositAmount * 1 ether) / VESTING_DURATION);
        assertEq(vestingEndsAt, block.timestamp + VESTING_DURATION);
        assertEq(lastUpdatedTimestamp, block.timestamp);
    }

    function testFuzzComplexDeposit(
        address account,
        uint256 depositAmount1,
        uint256 timeBetweenDeposits,
        uint256 depositAmount2
    ) public {
        vm.assume(account != address(0));
        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        depositAmount1 = bound(depositAmount1, 1, type(uint256).max / 1 ether - 1);
        depositAmount2 = bound(depositAmount2, 1, type(uint256).max / 1 ether - depositAmount1);
        timeBetweenDeposits = bound(timeBetweenDeposits, 1, VESTING_DURATION - 1);

        esSEAM.deposit(account, depositAmount1);
        vm.warp(block.timestamp + timeBetweenDeposits);

        uint256 timeUntilEnd = VESTING_DURATION - timeBetweenDeposits;
        uint256 currVestingAmount = (depositAmount1 * timeUntilEnd) / VESTING_DURATION;

        esSEAM.deposit(account, depositAmount2);

        (uint256 claimableAmount, uint256 decreasePerSecond, uint256 vestingEndsAt, uint256 lastUpdatedTimestamp) =
            esSEAM.vestingInfo(account);

        uint256 newVestingDuration = ((currVestingAmount * timeUntilEnd) + (depositAmount2 * VESTING_DURATION))
            / (currVestingAmount + depositAmount2);

        assertEq(claimableAmount, (depositAmount1 * timeBetweenDeposits) / VESTING_DURATION);
        assertEq(decreasePerSecond, ((currVestingAmount + depositAmount2) * 1 ether) / newVestingDuration);
        assertEq(vestingEndsAt, block.timestamp + newVestingDuration);
        assertEq(lastUpdatedTimestamp, block.timestamp);
    }

    function testFuzzDepositZeroAmountShouldNotChangeVestingInfo(address account) public {
        (
            uint256 claimableAmountBefore,
            uint256 decreasePerSecondBefore,
            uint256 vestingEndsAtBefore,
            uint256 lastUpdatedTimestampBefore
        ) = esSEAM.vestingInfo(account);

        esSEAM.deposit(account, 0);

        (
            uint256 claimableAmountAfter,
            uint256 decreasePerSecondAfter,
            uint256 vestingEndsAtAfter,
            uint256 lastUpdatedTimestampAfter
        ) = esSEAM.vestingInfo(account);

        assertEq(claimableAmountBefore, claimableAmountAfter);
        assertEq(decreasePerSecondBefore, decreasePerSecondAfter);
        assertEq(vestingEndsAtBefore, vestingEndsAtAfter);
        assertEq(lastUpdatedTimestampBefore, lastUpdatedTimestampAfter);
    }

    function testClaim() public {
        address account = makeAddr("account");
        uint256 depositAmount = 1000 ether;

        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        esSEAM.deposit(account, depositAmount);
        vm.warp(block.timestamp + VESTING_DURATION / 2);

        vm.startPrank(account);
        esSEAM.claim(account);
        vm.stopPrank();

        (uint256 claimableAmount,,, uint256 lastUpdatedTimestamp) = esSEAM.vestingInfo(account);

        assertEq(claimableAmount, 0);
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertApproxEqAbs(esSEAM.balanceOf(account), depositAmount / 2, REL_ROUNDING_TOLERANCE);
    }

    function testFuzzClaim(address account, uint256 depositAmount, uint256 timeBetweenActions) public {
        vm.assume(account != address(0));
        depositAmount = bound(depositAmount, 1 ether, type(uint256).max / 1 ether);
        timeBetweenActions = bound(timeBetweenActions, 0, type(uint48).max / 2);

        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        esSEAM.deposit(account, depositAmount);
        vm.warp(block.timestamp + timeBetweenActions);

        vm.startPrank(account);
        esSEAM.claim(account);
        vm.stopPrank();

        (uint256 claimableAmount,,, uint256 lastUpdatedTimestamp) = esSEAM.vestingInfo(account);

        uint256 timeElapsed = VESTING_DURATION > timeBetweenActions ? timeBetweenActions : VESTING_DURATION;

        assertEq(claimableAmount, 0);
        assertEq(lastUpdatedTimestamp, block.timestamp);
        assertApproxEqAbs(
            esSEAM.balanceOf(account),
            depositAmount - (depositAmount * timeElapsed) / VESTING_DURATION,
            ABS_ROUNDING_TOLERANCE
        );
    }

    function testDelegate() public {
        esSEAM.delegate(address(this));
        assertEq(esSEAM.getVotes(address(this)), esSEAM.totalSupply());
    }

    function testClaimBeforeDeposit_ShouldNotRevert() public {
        address account = makeAddr("account");

        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        esSEAM.claim(account);

        // deposit after claim should not revert
        uint256 depositAmount = 10 ether;
        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        esSEAM.deposit(account, depositAmount);
    }

    function testClaimAfterVestingEnd_DepositShouldNotRevert() public {
        address account = makeAddr("account");
        uint256 depositAmount = 10 ether;

        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        esSEAM.deposit(account, depositAmount);

        vm.warp(block.timestamp + VESTING_DURATION * 2);

        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        esSEAM.claim(account);

        // deposit after claim should not revert
        vm.mockCall(seam, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        esSEAM.deposit(account, depositAmount);
    }
}
