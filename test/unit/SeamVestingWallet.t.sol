// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SeamVestingWallet, Initializable} from "src/SeamVestingWallet.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/erc20/IERC20.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
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
                SeamVestingWallet.initialize.selector,
                address(this),
                _beneficiary,
                _token,
                _duration
            )
        );
        _proxy = SeamVestingWallet(address(proxy_));
    }

    function testDeployed() public {
        assertEq(_proxy.start(), 0);
        assertEq(_proxy.duration(), _duration);
        assertEq(_proxy.end(), type(uint64).max);
        assertEq(_proxy.released(), 0);
        assertEq(_proxy.releasable(), 0);
        assertEq(_proxy.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(_proxy.owner(), address(this));
        assertEq(_proxy.beneficiary(), _beneficiary);
    }

    function testUpgrade() public {
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

    function testSetStart() public {
        _proxy.setStart(1);
        assertEq(_proxy.start(), 1);
    }

    function testSetStartRevertIfNotOwner() public {
        vm.startPrank(_beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _beneficiary));
        _proxy.setStart(1);

        vm.stopPrank();
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzzWithdraw(uint256 withdrawAmount) public {
        deal(_token, address(_proxy), type(uint256).max);

        uint256 balanceThisBefore = IERC20(_token).balanceOf(address(this));
        uint256 balanceVestingWalletBefore = IERC20(_token).balanceOf(address(_proxy));
        _proxy.withdraw(withdrawAmount);

        assertEq(IERC20(_token).balanceOf(address(this)), balanceThisBefore + withdrawAmount);
        assertEq(IERC20(_token).balanceOf(address(_proxy)), balanceVestingWalletBefore - withdrawAmount);
    }

    function testRevertWithdrawIfNotOwner() public {
        vm.startPrank(_beneficiary);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _beneficiary));
        _proxy.withdraw(1);

        vm.stopPrank();
    }

    function testDelegate() public {
        vm.startPrank(_beneficiary);

        address delegate = makeAddr("delegate");

        vm.mockCall(_token, abi.encodeWithSelector(IVotes.delegate.selector), abi.encodePacked());
        vm.expectCall(_token, abi.encodeWithSelector(IVotes.delegate.selector, delegate));

        _proxy.delegate(delegate);

        vm.stopPrank();
    }

    function testDelegateRevertIfNotBeneficiary() public {
        vm.expectRevert(abi.encodeWithSelector(SeamVestingWallet.NotBeneficiary.selector, address(this)));
        _proxy.delegate(makeAddr("delegate"));
    }

    function testVestBeforeStart() public {
        _proxy.setStart(uint64(block.timestamp) + 1);

        assertEq(_proxy.releasable(), 0);
    }

    function testVestAfterEnd() public {
        deal(_token, address(_proxy), 1 ether);

        _proxy.setStart(uint64(block.timestamp) - _duration - 1);

        assertEq(_proxy.releasable(), 1 ether);
    }

    function testFuzzVestHalf(uint256 totalAllocation) public {
        _proxy.setStart(uint64(block.timestamp) - (_duration / 2));

        deal(_token, address(_proxy), totalAllocation);

        uint256 expectedVestedAmount = totalAllocation / 2;

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
}
