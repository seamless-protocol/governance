// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SeamEmissionManager} from "./SeamEmissionManager.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {SeamEmissionManagerStorage as Storage} from "./storage/SeamEmissionManagerStorage.sol";

/// @title SeamEmissionManagerV2
/// @author Seamless Protocol
/// @notice This contract is responsible for managing SEAM token emission.
contract SeamEmissionManagerV2 is SeamEmissionManager {
    /// @inheritdoc SeamEmissionManager
    function claim(address receiver) external override onlyRole(CLAIMER_ROLE) {
        Storage.Layout storage $ = Storage.layout();

        uint64 emissionStartTimestamp = $.emissionStartTimestamp;
        if (emissionStartTimestamp > block.timestamp) {
            revert EmissionsNotStarted(emissionStartTimestamp);
        }

        uint256 emissionPerSecond = $.emissionPerSecond;
        uint64 lastClaimedTimestamp = $.lastClaimedTimestamp;
        uint64 currentTimestamp = uint64(block.timestamp);
        uint256 emissionAmount = (currentTimestamp - lastClaimedTimestamp) * emissionPerSecond;

        // Check contract's SEAM balance and adjust emission amount if needed
        // When emission amount exceeds balance, emission rate will not result
        // in any more emissions until balance is increased (emission rate is not
        // applied retroactively for time elapsed while no balance was available)
        uint256 seamBalance = $.seam.balanceOf(address(this));
        if (emissionAmount > seamBalance) {
            emissionAmount = seamBalance;
        }

        SafeERC20.safeTransfer($.seam, receiver, emissionAmount);
        $.lastClaimedTimestamp = currentTimestamp;

        emit Claim(receiver, emissionAmount);
    }
}
