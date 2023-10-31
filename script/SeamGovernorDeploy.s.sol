// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamGovernor} from "../src/governance/SeamGovernor.sol";
import {SeamTimelockController} from "../src/governance/SeamTimelockController.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";

contract SeamDeployScript is Script {
    string public constant SEAM_GOVERNOR_SHORT_NAME = "SeamGovernorShort";
    uint48 public constant SEAM_GOVERNOR_SHORT_VOTING_DELAY = 2 * 7200; // 2 days
    uint32 public constant SEAM_GOVERNOR_SHORT_VOTING_PERIOD = 17280; // 3 days
    uint256 public constant SEAM_GOVERNOR_SHORT_PROPOSAL_THRESHOLD = 0;
    uint256 public constant SEAM_GOVERNOR_SHORT_NUMERATOR = 3;
    uint256 public constant SEAM_TIMELOCK_CONTROLLER_SHORT_MIN_DELAY = 4;

    string public constant SEAM_GOVERNOR_LONG_NAME = "SeamGovernorLong";
    uint48 public constant SEAM_GOVERNOR_LONG_VOTING_DELAY = 2 * 7200; // 2 days
    uint32 public constant SEAM_GOVERNOR_LONG_VOTING_PERIOD = 17280; // 3 days
    uint256 public constant SEAM_GOVERNOR_LONG_PROPOSAL_THRESHOLD = 0;
    uint256 public constant SEAM_GOVERNOR_LONG_NUMERATOR = 4;
    uint256 public constant SEAM_TIMELOCK_CONTROLLER_LONG_MIN_DELAY = 4;

    address public constant veSEAM = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    function getChainId() public view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        console.log("Deployer balance: ", deployerAddress.balance);
        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", getChainId());

        console.log("Deploying...");

        vm.startBroadcast(deployerPrivateKey);

        SeamTimelockController seamTimelockControllerShortImplementation = new SeamTimelockController();
        ERC1967Proxy seamTimelockControllerShortProxy = new ERC1967Proxy(
            address(seamTimelockControllerShortImplementation),
            abi.encodeWithSelector(
                SeamTimelockController.initialize.selector,
                SEAM_TIMELOCK_CONTROLLER_SHORT_MIN_DELAY,
                new address[](0),
                new address[](0),
                address(this)
            )
        );
        console.log(
            "Deployed SeamTimelockControllerShort proxy to: ",
            address(seamTimelockControllerShortProxy),
            " implementation: ",
            address(seamTimelockControllerShortImplementation)
        );

        SeamGovernor seamGovernorShortImplementation = new SeamGovernor();
        ERC1967Proxy seamGovernorShortProxy = new ERC1967Proxy(
            address(seamGovernorShortImplementation),
            abi.encodeWithSelector(
                SeamGovernor.initialize.selector,
                SEAM_GOVERNOR_SHORT_NAME,
                SEAM_GOVERNOR_SHORT_VOTING_DELAY,
                SEAM_GOVERNOR_SHORT_VOTING_PERIOD,
                SEAM_GOVERNOR_SHORT_PROPOSAL_THRESHOLD,
                SEAM_GOVERNOR_SHORT_NUMERATOR,
                IVotes(veSEAM),
                address(seamTimelockControllerShortProxy),
                address(this)
            )
        );
        console.log(
            "Deployed SeamGovernorShort proxy to: ",
            address(seamGovernorShortProxy),
            " implementation: ",
            address(seamGovernorShortImplementation)
        );

        SeamTimelockController seamTimelockControllerLongImplementation = new SeamTimelockController();
        ERC1967Proxy seamTimelockControllerLongProxy = new ERC1967Proxy(
            address(seamTimelockControllerLongImplementation),
            abi.encodeWithSelector(
                SeamTimelockController.initialize.selector,
                SEAM_TIMELOCK_CONTROLLER_LONG_MIN_DELAY,
                new address[](0),
                new address[](0),
                address(this)
            )
        );
        console.log(
            "Deployed SeamTimelockControllerShort proxy to: ",
            address(seamTimelockControllerLongProxy),
            " implementation: ",
            address(seamTimelockControllerLongImplementation)
        );

        SeamGovernor seamGovernorLongImplementation = new SeamGovernor();
        ERC1967Proxy seamGovernorLongProxy = new ERC1967Proxy(
            address(seamGovernorLongImplementation),
            abi.encodeWithSelector(
                SeamGovernor.initialize.selector,
                SEAM_GOVERNOR_LONG_NAME,
                SEAM_GOVERNOR_LONG_VOTING_DELAY,
                SEAM_GOVERNOR_LONG_VOTING_PERIOD,
                SEAM_GOVERNOR_LONG_PROPOSAL_THRESHOLD,
                SEAM_GOVERNOR_LONG_NUMERATOR,
                IVotes(veSEAM),
                address(seamTimelockControllerLongProxy),
                address(this)
            )
        );
        console.log(
            "Deployed SeamGovernorLong proxy to: ",
            address(seamGovernorLongProxy),
            " implementation: ",
            address(seamGovernorLongImplementation)
        );

        vm.stopBroadcast();
    }
}
