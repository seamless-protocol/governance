// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SeamGovernor} from "../src/SeamGovernor.sol";
import {SeamTimelockController} from "../src/SeamTimelockController.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {EscrowSeam} from "../src/EscrowSeam.sol";
import {Constants} from "../src/library/Constants.sol";
import {GovernorDeployer} from "./common/GovernorDeployer.sol";
import {EscrowSeamDeployer} from "./common/EscrowSeamDeployer.sol";

contract SeamFullGovernanceDeploy is GovernorDeployer, EscrowSeamDeployer {
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

        console.log("Deploying...\n");

        vm.startBroadcast(deployerPrivateKey);

        EscrowSeam esSEAM = deployEscrowSeam(Constants.SEAM_ADDRESS, Constants.VESTING_DURATION, deployerAddress);

        console.log("Deploying short governor and timelock controller...");

        GovernorParams memory shortGovernorParams = GovernorParams(
            Constants.GOVERNOR_SHORT_NAME,
            Constants.GOVERNOR_SHORT_VOTING_DELAY,
            Constants.GOVERNOR_SHORT_VOTING_PERIOD,
            Constants.GOVERNOR_SHORT_VOTE_NUMERATOR,
            Constants.GOVERNOR_SHORT_PROPOSAL_THRESHOLD,
            Constants.GOVERNOR_SHORT_QUORUM_NUMERATOR,
            Constants.SEAM_ADDRESS,
            address(esSEAM),
            Constants.TIMELOCK_CONTROLLER_SHORT_MIN_DELAY,
            Constants.GUARDIAN_WALLET,
            deployerAddress
        );
        (SeamGovernor governorShort, SeamTimelockController timelockShort) =
            deployGovernorAndTimelock(shortGovernorParams);

        console.log("Deploying long governor and timelock controller...");

        GovernorParams memory longGovernorParams = GovernorParams(
            Constants.GOVERNOR_LONG_NAME,
            Constants.GOVERNOR_LONG_VOTING_DELAY,
            Constants.GOVERNOR_LONG_VOTING_PERIOD,
            Constants.GOVERNOR_LONG_VOTE_NUMERATOR,
            Constants.GOVERNOR_LONG_PROPOSAL_THRESHOLD,
            Constants.GOVERNOR_LONG_QUORUM_NUMERATOR,
            Constants.SEAM_ADDRESS,
            address(esSEAM),
            Constants.TIMELOCK_CONTROLLER_LONG_MIN_DELAY,
            Constants.GUARDIAN_WALLET,
            deployerAddress
        );
        (SeamGovernor governorLong, SeamTimelockController timelockLong) = deployGovernorAndTimelock(longGovernorParams);

        timelockShort.grantRole(timelockShort.DEFAULT_ADMIN_ROLE(), address(timelockLong));
        console.log("DEFAULT_ADMIN_ROLE on short timelock controller granted to long timelock controller");

        timelockShort.revokeRole(timelockShort.DEFAULT_ADMIN_ROLE(), address(timelockShort));
        console.log("DEFAULT_ADMIN_ROLE on short timelock controller revoked from short timelock controller");

        timelockShort.revokeRole(timelockShort.DEFAULT_ADMIN_ROLE(), deployerAddress);
        console.log("DEFAULT_ADMIN_ROLE on short timelock controller revoked from deployer");

        timelockLong.revokeRole(timelockLong.DEFAULT_ADMIN_ROLE(), deployerAddress);
        console.log("DEFAULT_ADMIN_ROLE on long timelock controller revoked from deployer");

        governorShort.transferOwnership(address(timelockLong));
        console.log("Governor short ownership transferred to long timelock");
        governorLong.transferOwnership(address(timelockLong));
        console.log("Governor long ownership transferred to long timelock");

        esSEAM.transferOwnership(address(timelockLong));
        console.log("esSEAM ownership transferred to long timelock");

        vm.stopBroadcast();
    }
}
