// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ISeamAirdrop} from "../interfaces/ISeamAirdrop.sol";
import {IEscrowSeam} from "../interfaces/IEscrowSeam.sol";
import {Airdrop} from "./Airdrop.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/// @title Seam Airdrop
/// @notice Airdrop contract that transfers SEAM tokens
/// @dev New contract should be deployed for each airdrop
contract SeamAirdrop is ISeamAirdrop, Airdrop {
    uint256 public constant MAX_VESTING_PERCENTAGE = 100_00;

    IEscrowSeam public escrowSeam;
    uint256 public vestingPercentage;

    constructor(IERC20 _seam, IEscrowSeam _escrowSeam, uint256 _vestingPercentage, bytes32 _merkleRoot, address _owner)
        Airdrop(_seam, _merkleRoot, _owner)
    {
        if (_vestingPercentage > MAX_VESTING_PERCENTAGE) {
            revert InvalidVestingPercentage();
        }

        escrowSeam = _escrowSeam;
        vestingPercentage = _vestingPercentage;
    }

    /// @inheritdoc ISeamAirdrop
    function setVestingPercentage(uint256 _vestingPercentage) external onlyOwner {
        if (_vestingPercentage > MAX_VESTING_PERCENTAGE) {
            revert InvalidVestingPercentage();
        }

        vestingPercentage = _vestingPercentage;
        emit SetVestingPercentage(_vestingPercentage);
    }

    /// @inheritdoc Airdrop
    /// @dev This function transfers the SEAM tokens to recipients and vest SEAM tokens to esSEAM contract on behalf of recipients.
    function transfer(address recipient, uint256 amount) internal override {
        uint256 esSeamAmount = Math.mulDiv(amount, vestingPercentage, MAX_VESTING_PERCENTAGE);
        uint256 seamAmount = amount - esSeamAmount;

        if (esSeamAmount > 0) {
            seam.approve(address(escrowSeam), esSeamAmount);
            escrowSeam.deposit(recipient, esSeamAmount);
        }
        if (seamAmount > 0) {
            SafeERC20.safeTransfer(seam, recipient, seamAmount);
        }

        emit Transfer(recipient, seamAmount, esSeamAmount);
    }
}
