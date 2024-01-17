// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {SeamGovernor} from "../../src/SeamGovernor.sol";
import {SeamTimelockController} from "../../src/SeamTimelockController.sol";

contract GovernorDeployer is Script {
    struct GovernorParams {
        string name;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 voteNumerator;
        uint256 proposalThreshold;
        uint256 quorumNumerator;
        address seam;
        address esSEAM;
        uint256 timelockControllerMinDelay;
        address guardianWallet;
        address deployer;
    }

    function deployGovernorAndTimelock(GovernorParams memory params)
        public
        returns (SeamGovernor, SeamTimelockController)
    {
        SeamTimelockController timelockControllerImplementation = new SeamTimelockController();
        ERC1967Proxy timelockControllerProxy = new ERC1967Proxy(
            address(timelockControllerImplementation),
            abi.encodeWithSelector(
                SeamTimelockController.initialize.selector,
                params.timelockControllerMinDelay,
                new address[](0),
                new address[](0),
                params.deployer
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
                SeamGovernor.InitParams({
                    name: params.name,
                    initialVotingDelay: params.votingDelay,
                    initialVotingPeriod: params.votingPeriod,
                    proposalThresholdValue: params.proposalThreshold,
                    voteNumeratorValue: params.voteNumerator,
                    quorumNumeratorValue: params.quorumNumerator,
                    seam: IERC5805(params.seam),
                    esSEAM: IERC5805(params.esSEAM),
                    timelock: TimelockControllerUpgradeable(payable(timelockControllerProxy)),
                    initialOwner: params.deployer
                })
            )
        );
        console.log(
            "GovernorProxy deployed to: ", address(governorProxy), " implementation: ", address(governorImplementation)
        );

        SeamTimelockController timelockControllerProxyWrapped = SeamTimelockController(payable(timelockControllerProxy));
        timelockControllerProxyWrapped.grantRole(
            timelockControllerImplementation.PROPOSER_ROLE(), address(governorProxy)
        );
        console.log("PROPOSER_ROLE granted to governor");

        timelockControllerProxyWrapped.grantRole(
            timelockControllerImplementation.EXECUTOR_ROLE(), address(governorProxy)
        );
        console.log("EXECUTOR_ROLE granted to governor");

        timelockControllerProxyWrapped.grantRole(
            timelockControllerImplementation.CANCELLER_ROLE(), address(governorProxy)
        );
        console.log("CANCELLER_ROLE granted to governor");

        timelockControllerProxyWrapped.grantRole(
            timelockControllerImplementation.CANCELLER_ROLE(), params.guardianWallet
        );
        console.log("CANCELLER_ROLE granted to guardian wallet\n");

        return (SeamGovernor(payable(governorProxy)), timelockControllerProxyWrapped);
    }
}
