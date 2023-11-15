// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITransferStrategyBase} from "./interfaces/ITransferStrategyBase.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TransferStrategyBase is ITransferStrategyBase {
    address internal immutable incentivesController;
    address internal immutable rewardsAdmin;

    constructor(address _incentivesController, address _rewardsAdmin) {
        incentivesController = _incentivesController;
        rewardsAdmin = _rewardsAdmin;
    }

    modifier onlyIncentivesController() {
        if (msg.sender != incentivesController) {
            revert NotIncentivesController();
        }
        _;
    }

    modifier onlyRewardsAdmin() {
        if (msg.sender != rewardsAdmin) {
            revert NotRewardsAdmin();
        }
        _;
    }

    /// @inheritdoc ITransferStrategyBase
    function getIncentivesController()
        external
        view
        override
        returns (address)
    {
        return incentivesController;
    }

    /// @inheritdoc ITransferStrategyBase
    function getRewardsAdmin() external view override returns (address) {
        return rewardsAdmin;
    }

    /// @inheritdoc ITransferStrategyBase
    function performTransfer(
        address to,
        address reward,
        uint256 amount
    ) external virtual returns (bool);

    /// @inheritdoc ITransferStrategyBase
    function emergencyWithdrawal(
        address token,
        address to,
        uint256 amount
    ) external onlyRewardsAdmin {
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        emit EmergencyWithdrawal(msg.sender, token, to, amount);
    }
}