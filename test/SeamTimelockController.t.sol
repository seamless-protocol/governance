// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Votes} from "openzeppelin-contracts/governance/utils/Votes.sol";
import {TimelockController} from "openzeppelin-contracts/governance/TimelockController.sol";
import {Seam} from "../src/Seam.sol";
import {Seam} from "../src/Seam.sol";
import {SeamTimelockController} from "../src/SeamTimelockController.sol";
import {SeamGovernor} from "../src/SeamGovernor.sol";

contract SeamTimelockControllerTest is Test {
    uint256 public constant TIMELOCK_CONTROLLER_MIN_DELAY = 4;

    address public immutable _admin = makeAddr("admin");

    SeamTimelockController public timelockControllerProxy;

    function setUp() public {
        SeamTimelockController timelockControllerImplementation = new SeamTimelockController();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(timelockControllerImplementation),
            abi.encodeWithSelector(
                SeamTimelockController.initialize.selector,
                TIMELOCK_CONTROLLER_MIN_DELAY,
                new address[](0),
                new address[](0),
                _admin
            )
        );
        timelockControllerProxy = SeamTimelockController(payable(proxy));
    }

    function test_Deployed() public {
        assertEq(timelockControllerProxy.getMinDelay(), TIMELOCK_CONTROLLER_MIN_DELAY);
        assertTrue(timelockControllerProxy.hasRole(timelockControllerProxy.DEFAULT_ADMIN_ROLE(), _admin));
    }

    function test_Upgrade() public {
        vm.startPrank(_admin);

        address newImplementation = address(new SeamTimelockController());
        timelockControllerProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                timelockControllerProxy.DEFAULT_ADMIN_ROLE()
            )
        );
        timelockControllerProxy.upgradeToAndCall(newImplementation, abi.encodePacked());
    }

    function testFuzz_UpdateMinDelay(uint256 minDelay) public {
        vm.startPrank(_admin);
        timelockControllerProxy.updateDelay(minDelay);
        vm.stopPrank();
        assertEq(timelockControllerProxy.getMinDelay(), minDelay);
    }
}
