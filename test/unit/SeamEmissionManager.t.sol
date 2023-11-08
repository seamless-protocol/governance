// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamEmissionManager} from "src/SeamEmissionManager.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract SeamEmissionManagerTest is Test {
    address immutable seam = address(new ERC20Mock());
    uint256 immutable emissionPerSecond = 1 ether;

    SeamEmissionManager emissionManager;

    function setUp() public {
        SeamEmissionManager implementation = new SeamEmissionManager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                SeamEmissionManager.initialize.selector,
                seam,
                emissionPerSecond,
                address(this)
            )
        );
        emissionManager = SeamEmissionManager(address(proxy));
    }

    function testDeployed() public {
        assertEq(emissionManager.getSeam(), seam);
        assertEq(emissionManager.getEmissionPerSecond(), emissionPerSecond);
        assertEq(emissionManager.getLastClaimedTimestamp(), block.timestamp);
        assertEq(emissionManager.owner(), address(this));
    }

    function testSetEmissionPerSecond() public {
        uint256 newEmissionPerSecond = 2 ether;
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        assertEq(emissionManager.getEmissionPerSecond(), newEmissionPerSecond);
    }

    function testFuzzSetEmissionPerSecond(uint256 newEmissionPerSecond) public {
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        assertEq(emissionManager.getEmissionPerSecond(), newEmissionPerSecond);
    }

    function testFuzzSetEmissionPerSecondRevertNotOwner(address caller, uint256 newEmissionPerSecond) public {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        vm.stopPrank();
    }

    function testClaim() public {
        deal(seam, address(emissionManager), type(uint256).max);

        uint256 receiverBalanceBefore = IERC20(seam).balanceOf(address(this));
        uint256 emissionManagerBalanceBefore = IERC20(seam).balanceOf(address(emissionManager));

        vm.warp(block.timestamp + 5000);
        emissionManager.claim(address(this));

        assertEq(IERC20(seam).balanceOf(address(this)), receiverBalanceBefore + emissionPerSecond * 5000);
        assertEq(
            IERC20(seam).balanceOf(address(emissionManager)), emissionManagerBalanceBefore - emissionPerSecond * 5000
        );
    }

    function testFuzzClaim(address receiver, uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, type(uint64).max / emissionPerSecond);
        deal(seam, address(emissionManager), type(uint256).max);

        uint256 receiverBalanceBefore = IERC20(seam).balanceOf(receiver);
        uint256 emissionManagerBalanceBefore = IERC20(seam).balanceOf(address(emissionManager));

        vm.warp(block.timestamp + timeElapsed);
        emissionManager.claim(receiver);

        assertEq(IERC20(seam).balanceOf(receiver), receiverBalanceBefore + emissionPerSecond * timeElapsed);
        assertEq(
            IERC20(seam).balanceOf(address(emissionManager)),
            emissionManagerBalanceBefore - emissionPerSecond * timeElapsed
        );
    }
}
