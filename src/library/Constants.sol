// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Constants {
    string public constant TOKEN_NAME = "Seamless";
    string public constant TOKEN_SYMBOL = "SEAM";
    uint256 public constant MINT_AMOUNT = 100_000_000;
    address public constant TRANSFER_ROLES_TO = address(0);
    bool public constant REVOKE_DEPLOYER_PERM = false;

    string public constant GOVERNOR_SHORT_NAME = "SeamGovernorShort";
    uint48 public constant GOVERNOR_SHORT_VOTING_DELAY = 2 days;
    uint32 public constant GOVERNOR_SHORT_VOTING_PERIOD = 3 days;
    uint256 public constant GOVERNOR_SHORT_VOTE_NUMERATOR = 500; // 50%
    uint256 public constant GOVERNOR_SHORT_PROPOSAL_THRESHOLD = 200_000 ether; // 0.2%
    uint256 public constant GOVERNOR_SHORT_QUORUM_NUMERATOR = 15; // 1.5%
    uint256 public constant TIMELOCK_CONTROLLER_SHORT_MIN_DELAY = 2 days;

    string public constant GOVERNOR_LONG_NAME = "SeamGovernorLong";
    uint48 public constant GOVERNOR_LONG_VOTING_DELAY = 2 days;
    uint32 public constant GOVERNOR_LONG_VOTING_PERIOD = 10 days;
    uint256 public constant GOVERNOR_LONG_VOTE_NUMERATOR = 666; // 66.6%
    uint256 public constant GOVERNOR_LONG_PROPOSAL_THRESHOLD = 200_000 ether; // 0.2%
    uint256 public constant GOVERNOR_LONG_QUORUM_NUMERATOR = 15; // 1.5%
    uint256 public constant TIMELOCK_CONTROLLER_LONG_MIN_DELAY = 5 days;

    address public constant GUARDIAN_WALLET = 0xA1b5f2cc9B407177CD8a4ACF1699fa0b99955A22;

    uint256 public constant VESTING_DURATION = 365 days;

    //TODO: Change this addresses to the correct ones when deploying airdrop contracts
    address public constant SEAM_ADDRESS = 0x1C7a460413dD4e964f96D8dFC56E7223cE88CD85;
    address public constant ESCROW_SEAM_ADDRESS = address(0x0);
    uint256 public constant VESTING_PERCENTAGE = 10_00; // 10%
    bytes32 public constant MERKLE_ROOT = bytes32(0x0);
    address public constant SHORT_TIMELOCK_ADDRESS = address(0);

    // https://docs.base.org/base-contracts#ethereum-mainnet
    address public constant BASE_L1_BRIDGE = 0x3154Cf16ccdb4C6d922629664174b904d80F2C35;
}
