// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IATokenTransferStrategy} from "../interfaces/IATokenTransferStrategy.sol";
import {ITransferStrategyBase} from "../interfaces/ITransferStrategyBase.sol";
import {TransferStrategyBase} from "./TransferStrategyBase.sol";
import {WadRayMath} from '@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';

/// @title ERC20 transfer strategy
/// @notice Transfer strategy for the ERC20 token
/// @dev This contract should be used in order to claim ERC20 tokens for users.
///      This is made based on transfer strategies from Aave V3 periphery repository https://github.com/aave/aave-v3-periphery/tree/master
contract ATokenTransferStrategy is IATokenTransferStrategy, TransferStrategyBase {
    using WadRayMath for uint256;

    IERC20 public immutable rewardToken;
    IPool public immutable POOL;
    address public immutable underlyingAsset;

    /// @notice Initializes the contract
    /// @param _rewardToken ERC20 reward token
    /// @param _incentivesController IncentivesController contract address
    /// @param _rewardsAdmin RewardsAdmin contract address
    constructor(IERC20 _rewardToken, address _incentivesController, address _rewardsAdmin, address _underlyingAsset, address _pool)
        TransferStrategyBase(_incentivesController, _rewardsAdmin)
    {
        rewardToken = _rewardToken;
        underlyingAsset = _underlyingAsset;
        POOL = IPool(_pool);

    }

    /// @inheritdoc ITransferStrategyBase
    function performTransfer(address to, address, uint256 amount)
        external
        override(ITransferStrategyBase, TransferStrategyBase)
        onlyIncentivesController
        returns (bool)
    {
        uint256 withInterest = amount.rayMul(POOL.getReserveNormalizedIncome(underlyingAsset));
        SafeERC20.safeTransfer(rewardToken, to, amount);

        emit PerformTransfer(to, amount);
        return true;
    }
}
