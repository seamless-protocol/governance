// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SeamEmissionManager} from "../../src/SeamEmissionManager.sol";
import {SeamEmissionManagerV2} from "../../src/SeamEmissionManagerV2.sol";
import {Constants} from "../../src/library/Constants.sol";

contract SeamEmissionManagerV2ForkTest is Test {
    IERC20 immutable SEAM = IERC20(Constants.SEAM_ADDRESS);
    SeamEmissionManager emissionManager1 = SeamEmissionManager(Constants.SEAM_EMISSION_MANAGER1_ADDRESS);
    SeamEmissionManager emissionManager2 = SeamEmissionManager(Constants.SEAM_EMISSION_MANAGER2_ADDRESS);

    function setUp() public {
        vm.createSelectFork(vm.envString("FORK_URL"), 31645245);
    }

    function testUpgrade() public {
        address newImplementation = address(new SeamEmissionManagerV2());

        vm.startPrank(Constants.SHORT_TIMELOCK_ADDRESS);

        // Check that emission manager 1 reverts with insufficient balance. Since the vesting period is over
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        emissionManager1.claim(address(this));

        // Check that emission manager 2 claims successfully since the vesting period is not over
        emissionManager2.claim(address(this));

        vm.stopPrank();

        vm.startPrank(Constants.LONG_TIMELOCK_ADDRESS);
        emissionManager1.upgradeToAndCall(address(newImplementation), "");
        emissionManager2.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        vm.startPrank(Constants.SHORT_TIMELOCK_ADDRESS);
        emissionManager1.claim(address(this));
        emissionManager2.claim(address(this));

        // Check that emission manager 1 claims successfully the full balance since the vesting period is over
        assertEq(SEAM.balanceOf(address(emissionManager1)), 0);

        vm.stopPrank();
    }
}
