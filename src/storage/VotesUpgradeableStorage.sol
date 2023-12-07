// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VotesUpgradeable} from "openzeppelin-contracts-upgradeable/governance/utils/VotesUpgradeable.sol";

library VotesUpgradeableStorage {
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Votes")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0xe8b26c30fad74198956032a3533d903385d56dd795af560196f9c78d4af40d00;

    function layout() internal pure returns (VotesUpgradeable.VotesStorage storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
