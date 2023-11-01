// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constants {
    string constant TOKEN_NAME = "Seamless";
    string constant TOKEN_SYMBOL = "SEAM";
    uint256 constant MINT_AMOUNT = 100_000_000;
    address constant TRANSFER_ROLES_TO = 0xA1b5f2cc9B407177CD8a4ACF1699fa0b99955A22;
    bool constant REVOKE_DEPLOYER_PERM = true;

    string public constant GOVERNOR_SHORT_NAME = "SeamGovernorShort";
    uint48 public constant GOVERNOR_SHORT_VOTING_DELAY = 2 * 7200; // 2 days
    uint32 public constant GOVERNOR_SHORT_VOTING_PERIOD = 17280; // 3 days
    uint256 public constant GOVERNOR_SHORT_PROPOSAL_THRESHOLD = 0;
    uint256 public constant GOVERNOR_SHORT_NUMERATOR = 3;
    uint256 public constant TIMELOCK_CONTROLLER_SHORT_MIN_DELAY = 4;

    string public constant GOVERNOR_LONGNAME = "SeamGovernorShort";
    uint48 public constant GOVERNOR_LONGVOTING_DELAY = 2 * 7200; // 2 days
    uint32 public constant GOVERNOR_LONGVOTING_PERIOD = 17280; // 3 days
    uint256 public constant GOVERNOR_LONGPROPOSAL_THRESHOLD = 0;
    uint256 public constant GOVERNOR_LONGNUMERATOR = 3;
    uint256 public constant TIMELOCK_CONTROLLER_LONG_MIN_DELAY = 4;

    address public constant VOTING_TOKEN = 0x583cbB71773C86A67Aed4A0f2908A2bcA1d6731F;
    address public constant GUARDIAN_WALLET = address(0);
}
