// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ITransferStrategyBase} from "./ITransferStrategyBase.sol";

/// @title ERC20 transfer strategy Interface
/// @notice Interface for the ERC20 transfer strategy contract
interface IERC20TransferStrategy is ITransferStrategyBase {
    /// @notice Emitted when ERC20 tokens are transferred
    /// @param to Address to receive ERC20 tokens
    /// @param amount Amount of ERC20 tokens transferred
    event PerformTransfer(address indexed to, uint256 amount);
}
