// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IAirdrop} from "../interfaces/IAirdrop.sol";

/// @title Airdrop
/// @notice Contract for airdropping tokens to community members
abstract contract Airdrop is IAirdrop, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable seam;
    bytes32 public merkleRoot;

    mapping(address => bool) public hasClaimed;

    constructor(IERC20 _seam, bytes32 _merkleRoot, address _owner) Ownable(_owner) {
        seam = _seam;
        merkleRoot = _merkleRoot;
    }

    /// @inheritdoc IAirdrop
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /// @inheritdoc IAirdrop
    function claim(address recipient, uint256 amount, bytes32[] calldata merkleProof) external {
        if (hasClaimed[recipient]) {
            revert AlreadyClaimed(recipient);
        }
        if (!MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(recipient, amount)))) {
            revert InvalidProof();
        }

        hasClaimed[recipient] = true;
        transfer(recipient, amount);

        emit Claim(recipient, amount);
    }

    /// @notice Claim hook for transferring tokens
    /// @dev This function must be implemented by the inheriting contract
    /// @param account The account that claims tokens
    /// @param amount The amount of tokens to transfer
    function transfer(address account, uint256 amount) internal virtual;
}
