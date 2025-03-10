// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title IFeeSource
 * @author Seamless Protocol
 * @notice Interface for contracts that serve as sources of fees for the FeeKeeper
 * @dev Implementations must provide a token() method to identify the ERC20 token
 *      and a claim() method to distribute accumulated fees
 */
interface IFeeSource {
    /**
     * @notice Get the ERC20 token being split
     * @return The ERC20 token interface
     */
    function token() external view returns (IERC20);
    /**
     * @notice Claims accumulated fees and splits them between payees
     */
    function claim() external;
}
