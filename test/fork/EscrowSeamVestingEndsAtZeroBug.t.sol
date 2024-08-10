// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Seam} from "../../src/Seam.sol";
import {EscrowSeam} from "../../src/EscrowSeam.sol";
import {SeamGovernor} from "../../src/SeamGovernor.sol";
import {Constants} from "../../src/library/Constants.sol";

contract EscrowSeamVestingEndsAtZeroBugForkTest is Test {
    Seam public SEAM = Seam(Constants.SEAM_ADDRESS);
    EscrowSeam public esSEAM = EscrowSeam(Constants.ESCROW_SEAM_ADDRESS);

    // one address of the user which had 0 amount claim bug
    address public constant BUGGED_USER = 0x8d8335751DEFdfe2207e8DeCd67e462a08988844;

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 18130000);
    }

    function testConfirmBuggedUserState() public {
        (,, uint256 vestingEndsAt, uint256 lastUpdatedTimestamp) = esSEAM.vestingInfo(BUGGED_USER);
        assertEq(vestingEndsAt, 0);
        assertGt(lastUpdatedTimestamp, 0);
    }

    function testBuggedUserReverts_getClaimableAmount_deposit() public {
        vm.expectRevert(stdError.arithmeticError);
        esSEAM.getClaimableAmount(BUGGED_USER);

        uint256 depositAmount = 10 ether;
        deal(address(SEAM), address(this), depositAmount);
        SEAM.approve(address(esSEAM), depositAmount);
        vm.expectRevert(stdError.arithmeticError);
        esSEAM.deposit(BUGGED_USER, depositAmount);
    }

    function testFuzzBuggedUserShouldNotRevertAfterUpgrade(uint256 depositAmount) public {
        _upgradeEscrowSeam();

        // getClaimableAmount must not revert
        esSEAM.getClaimableAmount(BUGGED_USER);

        depositAmount = bound(depositAmount, 1, type(uint256).max / 1 ether);

        // deposit must not revert
        deal(address(SEAM), address(this), depositAmount);
        SEAM.approve(address(esSEAM), depositAmount);
        esSEAM.deposit(BUGGED_USER, depositAmount);

        (,, uint256 vestingEndsAt,) = esSEAM.vestingInfo(BUGGED_USER);
        assertGt(vestingEndsAt, 0);
    }

    function testFuzzZeroDepositShouldNotRevertAfterUpgrade(address account) public {
        _upgradeEscrowSeam();

        // deposit 0 amount must not revert
        esSEAM.deposit(account, 0);
    }

    function _upgradeEscrowSeam() internal {
        address newEscrowSeamImplementation = address(new EscrowSeam());
        vm.prank(Constants.LONG_TIMELOCK_ADDRESS);
        esSEAM.upgradeToAndCall(newEscrowSeamImplementation, "");
    }
}
