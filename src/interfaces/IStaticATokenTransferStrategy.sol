// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20TransferStrategy} from "../interfaces/IERC20TransferStrategy.sol";
import {ITransferStrategyBase} from "../interfaces/ITransferStrategyBase.sol";

/// @title ERC20 transfer strategy
/// @notice Transfer strategy for the ERC20 token
/// @dev This contract should be used in order to claim ERC20 tokens for users.
///      This is made based on transfer strategies from Aave V3 periphery repository https://github.com/aave/aave-v3-periphery/tree/master
interface IStaticATokenTransferStrategy is ITransferStrategyBase {
    event RewardsClaimed(address[] rewardAddress);
    event PerformTransfer(address indexed to, uint256 amount);

    /**
     * @notice Claims any accrued liquidity rewards from static tokens held in transfer strategy
     * @param to the address of the recipient
     * @param reward the address of the reward token
     */
    function claimRewards(address to, address[] calldata reward) external;
}
