// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardKeeperStorage as Storage} from "../storage/RewardKeeperStorage.sol";

interface IRewardKeeper {
    event ClaimedAndSetRate(address[] rewards, uint88[] rates);
    event SetRewardsController(address controller);
    event SetPool(address pool);
    event SetPeriod(uint256 period);

    error ZeroAddress(address target);
    error InsufficientTimeElapsed();
    error InvalidPeriod();
    error InvalidRewardToken();

    function pause() external;

    function unpause() external;
    function claimAndSetRate() external;

    function emergencyWithdrawalFromTransferStrategy(address token, address to, uint256 amt)
        external;

    function setRewardsController(address controller) external;

    function setPool(address newPool) external;

    function setPeriod(uint256 newPeriod) external;

    function getLayout() external view returns (Storage.Layout memory);
}
