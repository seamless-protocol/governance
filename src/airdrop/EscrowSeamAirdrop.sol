// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IEscrowSeamAirdrop} from "../interfaces/IEscrowSeamAirdrop.sol";
import {IEscrowSeam} from "../interfaces/IEscrowSeam.sol";
import {Airdrop} from "./Airdrop.sol";

/// @title Escrow Seam Airdrop
/// @notice Airdrop contract that deposits SEAM into the EscrowSeam contract
/// @notice New contract should be deployed for each airdrop
contract EscrowSeamAirdrop is IEscrowSeamAirdrop, Airdrop {
    IEscrowSeam public immutable escrowSeam;

    constructor(IERC20 _seam, IEscrowSeam _escrowSeam, bytes32 _merkleRoot, address _owner)
        Airdrop(_seam, _merkleRoot, _owner)
    {
        escrowSeam = _escrowSeam;
    }

    /// @inheritdoc Airdrop
    /// @dev This function deposits the SEAM tokens into the EscrowSeam contract
    function transfer(address recipient, uint256 amount) internal override {
        seam.approve(address(escrowSeam), amount);
        escrowSeam.deposit(recipient, amount);
    }
}
