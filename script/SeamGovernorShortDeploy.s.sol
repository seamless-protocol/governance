// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamGovernor} from "../src/SeamGovernor.sol";
import {SeamTimelockController} from "../src/SeamTimelockController.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";

contract SeamDeployScript is Script {
    string public constant GOVERNOR_NAME = "SeamGovernorShort";
    uint48 public constant GOVERNOR_VOTING_DELAY = 2 * 7200; // 2 days
    uint32 public constant GOVERNOR_VOTING_PERIOD = 17280; // 3 days
    uint256 public constant GOVERNOR_PROPOSAL_THRESHOLD = 0;
    uint256 public constant GOVERNOR_NUMERATOR = 3;
    uint256 public constant TIMELOCK_CONTROLLER_MIN_DELAY = 4;

    address public constant veSEAM = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant GUARDIAN_WALLET = address(0);

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

        SeamTimelockController timelockControllerImplementation = new SeamTimelockController();
        ERC1967Proxy timelockControllerProxy = new ERC1967Proxy(
            address(timelockControllerImplementation),
            abi.encodeWithSelector(
                SeamTimelockController.initialize.selector,
                TIMELOCK_CONTROLLER_MIN_DELAY,
                new address[](0),
                new address[](0),
                deployerAddress
            )
        );
        console.log(
            "TimelockControllerProxy deployed to: ",
            address(timelockControllerProxy),
            " implementation: ",
            address(timelockControllerImplementation)
        );

        SeamGovernor governorImplementation = new SeamGovernor();
        ERC1967Proxy governorProxy = new ERC1967Proxy(
            address(governorImplementation),
            abi.encodeWithSelector(
                SeamGovernor.initialize.selector,
                GOVERNOR_NAME,
                GOVERNOR_VOTING_DELAY,
                GOVERNOR_VOTING_PERIOD,
                GOVERNOR_PROPOSAL_THRESHOLD,
                GOVERNOR_NUMERATOR,
                IVotes(veSEAM),
                timelockControllerProxy,
                timelockControllerProxy
            )
        );
        console.log(
            "GovernorProxy deployed to: ", address(governorProxy), " implementation: ", address(governorImplementation)
        );

        SeamTimelockController timelockControllerProxyWrapped = SeamTimelockController(payable(timelockControllerProxy));
        timelockControllerProxyWrapped.grantRole(
            timelockControllerImplementation.PROPOSER_ROLE(), address(governorProxy)
        );
        timelockControllerProxyWrapped.grantRole(
            timelockControllerImplementation.EXECUTOR_ROLE(), address(governorProxy)
        );
        timelockControllerProxyWrapped.grantRole(
            timelockControllerImplementation.CANCELLER_ROLE(), address(governorProxy)
        );
        timelockControllerProxyWrapped.grantRole(timelockControllerImplementation.CANCELLER_ROLE(), GUARDIAN_WALLET);
        console.log("Roles granted");

        timelockControllerProxyWrapped.revokeRole(
            timelockControllerImplementation.DEFAULT_ADMIN_ROLE(), deployerAddress
        );
        console.log("DEFAULT_ADMIN_ROLE revoked from deployer");

        vm.stopBroadcast();
    }
}
