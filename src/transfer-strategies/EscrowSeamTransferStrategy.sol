// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISeamTransferStrategy} from "../interfaces/ISeamTransferStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEscrowSeam} from "../interfaces/IEscrowSeam.sol";
import {ITransferStrategyBase} from "../interfaces/ITransferStrategyBase.sol";
import {TransferStrategyBase} from "./TransferStrategyBase.sol";

/// @title EscrowSeam transfer strategy
/// @notice Transfer strategy for the Seam token
/// @dev This contract should be used in order to vest SEAM tokens inside EscrowSeam contract for users.
///      This is made based on transfer strategies from Aave V3 periphery repository https://github.com/aave/aave-v3-periphery/tree/master
contract EscrowSeamTransferStrategy is ISeamTransferStrategy, TransferStrategyBase {
    IERC20 public immutable seam;
    IEscrowSeam public immutable escrowSeam;

    /// @notice Initializes the contract
    /// @param _seam SEAM token
    /// @param _escrowSeam EscrowSeam contract
    /// @param _incentivesController IncentivesController contract address
    /// @param _rewardsAdmin RewardsAdmin contract address
    constructor(IERC20 _seam, IEscrowSeam _escrowSeam, address _incentivesController, address _rewardsAdmin)
        TransferStrategyBase(_incentivesController, _rewardsAdmin)
    {
        seam = _seam;
        escrowSeam = _escrowSeam;
    }

    /// @inheritdoc ITransferStrategyBase
    function performTransfer(address to, address, uint256 amount)
        external
        override(ITransferStrategyBase, TransferStrategyBase)
        onlyIncentivesController
        returns (bool)
    {
        seam.approve(address(escrowSeam), amount);
        escrowSeam.deposit(to, amount);
        emit PerformTransfer(to, amount);
        return true;
    }
}
