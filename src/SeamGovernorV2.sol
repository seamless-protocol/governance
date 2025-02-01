// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC5805} from "openzeppelin-contracts/interfaces/IERC5805.sol";
import {SeamGovernorStorage as Storage} from "./storage/SeamGovernorStorage.sol";
import {SeamGovernor} from "./SeamGovernor.sol";

/// @title SeamGovernorV2
/// @author Seamless Protocol
/// @notice Governor contract of the Seamless Protocol used for both short and long governors
/// @custom:oz-upgrades-from SeamGovernor
contract SeamGovernorV2 is SeamGovernor {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initializeV2(IERC5805 stkSEAM) external reinitializer(2) {
        Storage.layout().stkSEAM = stkSEAM;
    }

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
