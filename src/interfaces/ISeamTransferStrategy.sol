// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ITransferStrategyBase} from "./ITransferStrategyBase.sol";

/// @title Seam transfer strategy Interface
/// @notice Interface for the Seam transfer strategy contract
interface ISeamTransferStrategy is ITransferStrategyBase {
    /// @notice Emitted when SEAM tokens are transferred
    /// @param to Address to receive SEAM tokens
    /// @param amount Amount of SEAM tokens transferred
    event PerformTransfer(address indexed to, uint256 amount);
}
