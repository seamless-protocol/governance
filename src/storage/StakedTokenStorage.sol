// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library StakedTokenStorage {
    struct RewardTokenData {
        uint256 rewardPerStakedToken;
        uint256 totalAccruedRewards;
        uint256 lastUpdatedTimestamp;
    }

    struct Layout {
        address stakedToken;
        uint256 totalStaked;
        address[] rewardTokens;
        mapping(address => RewardTokenData) rewardTokenData;
        // rewardToken => emissionPerSecond
        mapping(address => uint256) emissionPerSecond;
        // user => stakedBalance
        mapping(address => uint256) stakedBalances;
        // user => rewardToken => rewardDebt
        mapping(address => mapping(address => uint256)) rewardDebt;
        // user => rewardToken => accruedRewards
        mapping(address => mapping(address => uint256)) accruedRewards;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.EscrowSeam")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x6393c68bbda65a43373480543c4f1ff15eb61969ce223f59d8fd1889e26cc300;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
