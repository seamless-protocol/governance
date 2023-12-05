// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ISeamAirdrop} from "./interfaces/ISeamAirdrop.sol";
import {IEscrowSeam} from "./interfaces/IEscrowSeam.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/// @title Seam Airdrop
/// @notice Airdrop contract that transfers SEAM tokens
/// @dev New contract should be deployed for each airdrop
contract SeamAirdrop is ISeamAirdrop, Ownable {
    uint256 public constant MAX_VESTING_PERCENTAGE = 100_00;

    IEscrowSeam public escrowSeam;
    IERC20 public immutable seam;
    uint256 public vestingPercentage;
    bytes32 public merkleRoot;

    mapping(address => bool) public hasClaimed;

    constructor(IERC20 _seam, IEscrowSeam _escrowSeam, uint256 _vestingPercentage, bytes32 _merkleRoot, address _owner)
        Ownable(_owner)
    {
        if (_vestingPercentage > MAX_VESTING_PERCENTAGE) {
            revert InvalidVestingPercentage();
        }

        seam = _seam;
        escrowSeam = _escrowSeam;
        vestingPercentage = _vestingPercentage;
        merkleRoot = _merkleRoot;
    }

    /// @inheritdoc ISeamAirdrop
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /// @inheritdoc ISeamAirdrop
    function setVestingPercentage(uint256 _vestingPercentage) external onlyOwner {
        if (_vestingPercentage > MAX_VESTING_PERCENTAGE) {
            revert InvalidVestingPercentage();
        }

        vestingPercentage = _vestingPercentage;
        emit VestingPercentageSet(_vestingPercentage);
    }

    /// @inheritdoc ISeamAirdrop
    function claim(address recipient, uint256 amount, bytes32[] calldata merkleProof) external {
        if (hasClaimed[recipient]) {
            revert AlreadyClaimed(recipient);
        }
        if (!MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(recipient, amount)))) {
            revert InvalidProof();
        }

        uint256 esSeamAmount = Math.mulDiv(amount, vestingPercentage, MAX_VESTING_PERCENTAGE);
        uint256 seamAmount = amount - esSeamAmount;

        if (esSeamAmount > 0) {
            seam.approve(address(escrowSeam), esSeamAmount);
            escrowSeam.deposit(recipient, esSeamAmount);
        }
        if (seamAmount > 0) {
            SafeERC20.safeTransfer(seam, recipient, seamAmount);
        }

        hasClaimed[recipient] = true;
        emit Claim(recipient, seamAmount, esSeamAmount);
    }

    /// @inheritdoc ISeamAirdrop
    function withdraw(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        SafeERC20.safeTransfer(token, recipient, amount);
        emit Withdraw(address(token), recipient, amount);
    }
}
