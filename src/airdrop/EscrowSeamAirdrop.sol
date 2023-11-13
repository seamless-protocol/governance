// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IEscrowSeam} from "../interfaces/IEscrowSeam.sol";
import {Airdrop} from "./Airdrop.sol";

contract EscrowSeamAirdrop is Airdrop {
    IEscrowSeam public immutable escrowSeam;

    constructor(IERC20 _seam, IEscrowSeam _escrowSeam, bytes32 _merkleRoot, address _owner)
        Airdrop(_seam, _merkleRoot, _owner)
    {
        escrowSeam = _escrowSeam;
    }

    function transfer(address recipient, uint256 amount) internal override {
        seam.approve(address(escrowSeam), amount);
        escrowSeam.deposit(recipient, amount);
    }
}
