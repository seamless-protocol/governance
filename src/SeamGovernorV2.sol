// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GovernorUpgradeable} from "openzeppelin-contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorStorageUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import {GovernorVotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {IGovernor} from "openzeppelin-contracts/governance/IGovernor.sol";
import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";
import {SeamGovernorStorage as Storage} from "./storage/SeamGovernorStorage.sol";
import {GovernorCountingFractionUpgradeable} from "./GovernorCountingFractionUpgradeable.sol";
import {SeamGovernor} from "./SeamGovernor.sol";

/// @title SeamGovernorV2
/// @author Seamless Protocol
/// @notice Governor contract of the Seamless Protocol used for both short and long governors
/// @custom:oz-upgrades-from SeamGovernor
contract SeamGovernorV2 is SeamGovernor {
    /// @notice Initializes the governor with the stkSEAM token
    /// @param stkSEAM The stkSEAM token
    function initializeV2(IERC5805 stkSEAM) external reinitializer(2) {
        Storage.layout().stkSEAM = stkSEAM;
    }

    /// @notice Returns the tokens used for voting
    /// @return tokens_ The tokens used for voting
    function tokens() public view virtual returns (IERC5805[] memory tokens_) {
        tokens_ = new IERC5805[](3);
        tokens_[0] = token();
        tokens_[1] = Storage.layout().esSEAM;
        tokens_[2] = Storage.layout().stkSEAM;
    }

    /// @inheritdoc GovernorVotesUpgradeable
    function _getVotes(address account, uint256 timepoint, bytes memory /*params*/ )
        internal
        view
        override
        returns (uint256)
    {
        Storage.Layout storage $ = Storage.layout();
        return token().getPastVotes(account, timepoint) + $.esSEAM.getPastVotes(account, timepoint)
            + $.stkSEAM.getPastVotes(account, timepoint);
    }
}
