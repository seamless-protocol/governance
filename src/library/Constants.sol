// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constants {
    string constant TOKEN_NAME = "Seamless";
    string constant TOKEN_SYMBOL = "SEAM";
    uint256 constant MINT_AMOUNT = 100_000_000;
    address constant TRANSFER_ROLES_TO = 0xA1b5f2cc9B407177CD8a4ACF1699fa0b99955A22;
    bool constant REVOKE_DEPLOYER_PERM = true;

    string public constant GOVERNOR_SHORT_NAME = "SeamGovernorShort";
    uint48 public constant GOVERNOR_SHORT_VOTING_DELAY = 2 days;
    uint32 public constant GOVERNOR_SHORT_VOTING_PERIOD = 3 days;
    uint256 public constant GOVERNOR_SHORT_PROPOSAL_NUMERATOR = 5;
    uint256 public constant GOVERNOR_SHORT_NUMERATOR = 4;
    uint256 public constant TIMELOCK_CONTROLLER_SHORT_MIN_DELAY = 2 days;

    string public constant GOVERNOR_LONG_NAME = "SeamGovernorLong";
    uint48 public constant GOVERNOR_LONG_VOTING_DELAY = 2 days;
    uint32 public constant GOVERNOR_LONG_VOTING_PERIOD = 10 days;
    uint256 public constant GOVERNOR_LONG_PROPOSAL_NUMERATOR = 5;
    uint256 public constant GOVERNOR_LONG_NUMERATOR = 3;
    uint256 public constant TIMELOCK_CONTROLLER_LONG_MIN_DELAY = 5 days;

    address public constant VOTING_TOKEN = 0x583cbB71773C86A67Aed4A0f2908A2bcA1d6731F;
    address public constant GUARDIAN_WALLET = address(0);
}
