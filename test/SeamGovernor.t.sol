// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Votes} from "openzeppelin-contracts/governance/utils/Votes.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {Seam} from "../src/Seam.sol";
import {SeamGovernor} from "../src/SeamGovernor.sol";

contract SeamGovernorTest is Test {
    string public constant NAME = "Governor name";
    uint48 public constant VOTING_DELAY = 1234;
    uint32 public constant VOTING_PERIOD = 5678;
    uint256 public constant PROPOSAL_THRESHOLD = 9012;
    uint256 public constant NUMERATOR = 34;

    address immutable _veSEAM = makeAddr("veSEAM");
    address immutable _timelockController = makeAddr("timelockController");
    address immutable _initialOwner = makeAddr("initialOwner");

    SeamGovernor public governorImplementation;
    SeamGovernor public governorProxy;

    function setUp() public {
        vm.mockCall(_veSEAM, abi.encodeWithSelector(Votes.clock.selector), abi.encode(block.timestamp));
        governorImplementation = new SeamGovernor();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(governorImplementation),
            abi.encodeWithSelector(
                SeamGovernor.initialize.selector,
                NAME,
                VOTING_DELAY,
                VOTING_PERIOD,
                PROPOSAL_THRESHOLD,
                NUMERATOR,
                IVotes(_veSEAM),
                TimelockControllerUpgradeable(payable(_timelockController)),
                _initialOwner
            )
        );
        governorProxy = SeamGovernor(payable(proxy));
    }

    function test_Deployed() public {
        assertEq(governorProxy.name(), NAME);
        assertEq(governorProxy.votingDelay(), VOTING_DELAY);
        assertEq(governorProxy.votingPeriod(), VOTING_PERIOD);
        assertEq(governorProxy.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(governorProxy.quorumNumerator(), NUMERATOR);
        assertEq(address(governorProxy.token()), _veSEAM);
        assertEq(address(governorProxy.timelock()), _timelockController);
        assertEq(governorProxy.owner(), _initialOwner);
    }

    function test_Upgrade() public {
        vm.startPrank(_initialOwner);

        address newImplementation = address(new SeamGovernor());
        governorProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        governorProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());
    }
}
