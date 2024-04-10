// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SeamVestingWallet, Initializable} from "src/SeamVestingWallet.sol";
import {ISeamVestingWallet} from "src/interfaces/ISeamVestingWallet.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";

contract SeamVestingWalletTest is Test {
    SeamVestingWallet _implementation;
    SeamVestingWallet _proxy;

    uint64 constant _duration = 300;

    uint256 constant _blockTimestamp = 1699383535; // Tue Nov 07 2023 18:58:55 UTC

    address immutable _beneficiary = makeAddr("beneficiary");
    address immutable _token = address(new ERC20Mock());

    function setUp() public {
        vm.warp(_blockTimestamp);

        _implementation = new SeamVestingWallet();
        ERC1967Proxy proxy_ = new ERC1967Proxy(
            address(_implementation),
            abi.encodeWithSelector(
                SeamVestingWallet.initialize.selector, address(this), _beneficiary, _token, _duration
            )
        );
        _proxy = SeamVestingWallet(address(proxy_));
    }

    function test_Deployed() public {
        assertEq(_proxy.start(), 0);
        assertEq(_proxy.duration(), _duration);
        assertEq(_proxy.end(), type(uint64).max);
        assertEq(_proxy.released(), 0);
        assertEq(_proxy.releasable(), 0);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(_proxy.owner(), address(this));
        assertEq(_proxy.beneficiary(), _beneficiary);
    }

    function test_Upgrade() public {
        address newImplementation = address(new SeamVestingWallet());

        _proxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        // Revert on upgrade when not owner
        vm.startPrank(_beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _beneficiary));
        _proxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        vm.stopPrank();

        // Revert when already initialized
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _proxy.upgradeToAndCall(
            address(newImplementation),
            abi.encodeWithSelector(
                SeamVestingWallet.initialize.selector, address(this), _beneficiary, _token, _duration
            )
        );
    }

    function test_SetStart() public {
        _proxy.setStart(1);
        assertEq(_proxy.start(), 1);
    }

    function test_SetStart_RevertIf_NotOwner() public {
        vm.startPrank(_beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _beneficiary));
        _proxy.setStart(1);

        vm.stopPrank();
    }

    function test_SetDuration() public {
        _proxy.setDuration(1);
        assertEq(_proxy.duration(), 1);
    }

    function test_SetDuration_RevertIf_NotOwner() public {
        vm.startPrank(_beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _beneficiary));
        _proxy.setDuration(1);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_Transfer(uint256 withdrawAmount) public {
        deal(_token, address(_proxy), type(uint256).max);

        uint256 balanceThisBefore = IERC20(_token).balanceOf(address(this));
        uint256 balanceVestingWalletBefore = IERC20(_token).balanceOf(address(_proxy));
        _proxy.transfer(_token, address(this), withdrawAmount);

        assertEq(IERC20(_token).balanceOf(address(this)), balanceThisBefore + withdrawAmount);
        assertEq(IERC20(_token).balanceOf(address(_proxy)), balanceVestingWalletBefore - withdrawAmount);
    }

    function test_Withdraw_RevertIf_NotOwner() public {
        vm.startPrank(_beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _beneficiary));
        _proxy.transfer(_token, address(this), 1);

        vm.stopPrank();
    }

    function test_Delegate() public {
        vm.startPrank(_beneficiary);

        address delegate = makeAddr("delegate");

        vm.mockCall(_token, abi.encodeWithSelector(IVotes.delegate.selector), abi.encodePacked());
        vm.expectCall(_token, abi.encodeWithSelector(IVotes.delegate.selector, delegate));

        _proxy.delegate(delegate);

        vm.stopPrank();
    }

    function test_Delegate_RevertIf_NotBeneficiary() public {
        vm.expectRevert(abi.encodeWithSelector(ISeamVestingWallet.NotBeneficiary.selector, address(this)));
        _proxy.delegate(makeAddr("delegate"));
    }

    function test_VestBeforeStart() public {
        _proxy.setStart(uint64(block.timestamp) + 1);

        assertEq(_proxy.releasable(), 0);
    }

    function test_VestAfterEnd() public {
        deal(_token, address(_proxy), 1 ether);

        _proxy.setStart(uint64(block.timestamp) - _duration - 1);

        assertEq(_proxy.releasable(), 1 ether);
    }

    function testFuzz_Vest(uint256 totalAllocation, uint64 percentVested) public {
        percentVested = uint64(bound(percentVested, 1, 100));

        _proxy.setStart(uint64(block.timestamp) - ((_duration * percentVested) / 100));

        deal(_token, address(_proxy), totalAllocation);

        uint256 expectedVestedAmount = Math.mulDiv(totalAllocation, percentVested, 100);

        assertEq(_proxy.releasable(), expectedVestedAmount);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
        assertEq(_proxy.released(), 0);

        uint256 balanceBeneficiaryBefore = IERC20(_token).balanceOf(address(_beneficiary));
        uint256 balanceVestingWalletBefore = IERC20(_token).balanceOf(address(_proxy));

        _proxy.release();

        assertEq(IERC20(_token).balanceOf(address(_beneficiary)), balanceBeneficiaryBefore + expectedVestedAmount);
        assertEq(IERC20(_token).balanceOf(address(_proxy)), balanceVestingWalletBefore - expectedVestedAmount);
        assertEq(_proxy.released(), expectedVestedAmount);
        assertEq(_proxy.releasable(), 0);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
    }

    function testFuzz_VestAddedBalance(uint256 startingAllocation, uint256 addedAmount, uint64 percentVested) public {
        percentVested = uint64(bound(percentVested, 0, 100));
        startingAllocation = bound(startingAllocation, 0, type(uint256).max - addedAmount);

        _proxy.setStart(uint64(block.timestamp) - ((_duration * percentVested) / 100));

        deal(_token, address(_proxy), startingAllocation);

        uint256 expectedVestedAmount = Math.mulDiv(startingAllocation, percentVested, 100);

        assertEq(_proxy.releasable(), expectedVestedAmount);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
        assertEq(_proxy.released(), 0);

        uint256 expectedVestedAmountAfterTransfer = Math.mulDiv(startingAllocation + addedAmount, percentVested, 100);

        uint256 snapshot = vm.snapshot();

        _proxy.release();

        ERC20Mock(_token).mint(address(_proxy), addedAmount);

        assertEq(_proxy.releasable(), expectedVestedAmountAfterTransfer - expectedVestedAmount);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmountAfterTransfer);
        assertEq(_proxy.released(), expectedVestedAmount);

        vm.revertTo(snapshot);

        ERC20Mock(_token).mint(address(_proxy), addedAmount);

        assertEq(_proxy.releasable(), expectedVestedAmountAfterTransfer);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmountAfterTransfer);
        assertEq(_proxy.released(), 0);
    }

    function testFuzz_VestRemovedBalance(uint256 startingAllocation, uint256 removedAmount, uint64 percentVested)
        public
    {
        percentVested = uint64(bound(percentVested, 0, 100));
        removedAmount = bound(removedAmount, 0, startingAllocation);

        uint256 expectedVestedAmount = Math.mulDiv(startingAllocation, percentVested, 100);
        removedAmount = bound(removedAmount, 0, startingAllocation - expectedVestedAmount);

        _proxy.setStart(uint64(block.timestamp) - ((_duration * percentVested) / 100));

        deal(_token, address(_proxy), startingAllocation);

        assertEq(_proxy.releasable(), expectedVestedAmount);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmount);
        assertEq(_proxy.released(), 0);

        uint256 expectedVestedAmountAfterTransfer = Math.mulDiv(startingAllocation - removedAmount, percentVested, 100);

        uint256 snapshot = vm.snapshot();

        _proxy.release();

        _proxy.transfer(_token, address(this), removedAmount);

        assertEq(_proxy.releasable(), 0);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmountAfterTransfer);
        assertEq(_proxy.released(), expectedVestedAmount);

        vm.revertTo(snapshot);

        _proxy.transfer(_token, address(this), removedAmount);

        assertEq(_proxy.releasable(), expectedVestedAmountAfterTransfer);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), expectedVestedAmountAfterTransfer);
        assertEq(_proxy.released(), 0);
    }
}
