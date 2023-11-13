// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ISeamAirdrop} from "../interfaces/ISeamAirdrop.sol";
import {Airdrop} from "./Airdrop.sol";

/// @title Seam Airdrop
/// @notice Airdrop contract that transfers SEAM tokens
/// @dev New contract should be deployed for each airdrop
contract SeamAirdrop is ISeamAirdrop, Airdrop {
    constructor(IERC20 _seam, bytes32 _merkleRoot, address _owner) Airdrop(_seam, _merkleRoot, _owner) {}

    /// @inheritdoc Airdrop
    /// @dev This function transfers the SEAM tokens to recipients
    function transfer(address recipient, uint256 amount) internal override {
        SafeERC20.safeTransfer(seam, recipient, amount);
    }
}
