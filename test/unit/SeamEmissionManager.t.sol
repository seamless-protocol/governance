// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamEmissionManager} from "src/SeamEmissionManager.sol";
import {ISeamEmissionManager} from "src/interfaces/ISeamEmissionManager.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
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
                address(this),
                address(this),
                block.timestamp
            )
        );
        emissionManager = SeamEmissionManager(address(proxy));
    }

    function test_SetUp() public {
        assertEq(emissionManager.getSeam(), seam);
        assertEq(emissionManager.getEmissionPerSecond(), emissionPerSecond);
        assertEq(emissionManager.getEmissionStartTimestamp(), block.timestamp);
        assertEq(emissionManager.getLastClaimedTimestamp(), block.timestamp);
        assertTrue(emissionManager.hasRole(emissionManager.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(emissionManager.hasRole(emissionManager.CLAIMER_ROLE(), address(this)));
    }

    function test_SetEmissionStartTimestamp() public {
        uint64 emissionStartTimestamp = uint64(block.timestamp) + 1;
        emissionManager.setEmissionStartTimestamp(emissionStartTimestamp);
        assertEq(emissionManager.getEmissionStartTimestamp(), emissionStartTimestamp);
        assertEq(emissionManager.getLastClaimedTimestamp(), 0);
    }

    function testFuzz_SetEmissionStartTimestamp(uint64 emissionStartTimestamp) public {
        emissionStartTimestamp = uint64(bound(emissionStartTimestamp, uint64(block.timestamp) + 1, type(uint64).max));
        emissionManager.setEmissionStartTimestamp(emissionStartTimestamp);
        assertEq(emissionManager.getEmissionStartTimestamp(), emissionStartTimestamp);
        assertEq(emissionManager.getLastClaimedTimestamp(), 0);
    }

    function testFuzz_SetEmissionStartTimestamp_RevertIf_NotDefaultAdmin(address caller, uint48 emissionStartTimestamp)
        public
    {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, emissionManager.DEFAULT_ADMIN_ROLE()
            )
        );
        emissionManager.setEmissionStartTimestamp(emissionStartTimestamp);
        vm.stopPrank();
    }

    function test_SetEmissionPerSecond() public {
        uint256 newEmissionPerSecond = 2 ether;
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        assertEq(emissionManager.getEmissionPerSecond(), newEmissionPerSecond);
    }

    function testFuzz_SetEmissionPerSecond(uint256 newEmissionPerSecond) public {
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        assertEq(emissionManager.getEmissionPerSecond(), newEmissionPerSecond);
    }

    function testFuzz_SetEmissionPerSecond_RevertIf_NotDefaultAdmin(address caller, uint256 newEmissionPerSecond)
        public
    {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, emissionManager.DEFAULT_ADMIN_ROLE()
            )
        );
        emissionManager.setEmissionPerSecond(newEmissionPerSecond);
        vm.stopPrank();
    }

    function test_Claim() public {
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

    function test_Claim_RevertIf_NotStarted() public {
        deal(seam, address(emissionManager), type(uint256).max);

        emissionManager.setEmissionStartTimestamp(uint64(block.timestamp) + 1);

        vm.expectRevert(abi.encodeWithSelector(ISeamEmissionManager.EmissionsNotStarted.selector, block.timestamp + 1));
        emissionManager.claim(address(this));
    }

    function testFuzz_Claim(address receiver, uint256 timeElapsed) public {
        vm.assume(receiver != address(0));
        timeElapsed = bound(timeElapsed, 0, type(uint32).max / emissionPerSecond);
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

    function testFuzz_Claim_RevertIf_NotClaimer(address caller) public {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, emissionManager.CLAIMER_ROLE()
            )
        );
        emissionManager.claim(address(this));
        vm.stopPrank();
    }
}
