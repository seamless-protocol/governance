// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constants {
    string public constant TOKEN_NAME = "Seamless";
    string public constant TOKEN_SYMBOL = "SEAM";
    uint256 public constant MINT_AMOUNT = 100_000_000;
    address public constant TRANSFER_ROLES_TO =
        0xA1b5f2cc9B407177CD8a4ACF1699fa0b99955A22;
    bool public constant REVOKE_DEPLOYER_PERM = true;

    string public constant GOVERNOR_SHORT_NAME = "SeamGovernorShort";
    uint48 public constant GOVERNOR_SHORT_VOTING_DELAY = 2 days;
    uint32 public constant GOVERNOR_SHORT_VOTING_PERIOD = 3 days;
    uint256 public constant GOVERNOR_SHORT_VOTE_NUMERATOR = 500; // 50%
    uint256 public constant GOVERNOR_SHORT_PROPOSAL_NUMERATOR = 5; // 0.5%
    uint256 public constant GOVERNOR_SHORT_NUMERATOR = 4;
    uint256 public constant TIMELOCK_CONTROLLER_SHORT_MIN_DELAY = 2 days;

    string public constant GOVERNOR_LONG_NAME = "SeamGovernorLong";
    uint48 public constant GOVERNOR_LONG_VOTING_DELAY = 2 days;
    uint32 public constant GOVERNOR_LONG_VOTING_PERIOD = 10 days;
    uint256 public constant GOVERNOR_LONG_VOTE_NUMERATOR = 666; // 66.6%
    uint256 public constant GOVERNOR_LONG_PROPOSAL_NUMERATOR = 5; // 0.5%
    uint256 public constant GOVERNOR_LONG_NUMERATOR = 3;
    uint256 public constant TIMELOCK_CONTROLLER_LONG_MIN_DELAY = 5 days;

    address public constant VOTING_TOKEN =
        0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85;
    address public constant GUARDIAN_WALLET = address(0);

    uint256 public constant VESTING_DURATION = 365 days;
}
