// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ISeamAirdrop} from "./interfaces/ISeamAirdrop.sol";

/// @title SeamAirDrop
/// @notice Contract for airdropping tokens to community members
/// @dev For every new airdrop, a new contract should be deployed
contract SeamAirdrop is ISeamAirdrop, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable seam;
    bytes32 public merkleRoot;

    mapping(address => bool) public hasClaimed;

    constructor(IERC20 _seam, bytes32 _merkleRoot, address _owner) Ownable(_owner) {
        seam = _seam;
        merkleRoot = _merkleRoot;
    }

    /// @inheritdoc ISeamAirdrop
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /// @inheritdoc ISeamAirdrop
    function claim(address recipient, uint256 amount, bytes32[] calldata merkleProof) external {
        if (hasClaimed[recipient]) {
            revert AlreadyClaimed(recipient);
        }
        if (!MerkleProof.verify(merkleProof, merkleRoot, keccak256(abi.encodePacked(recipient, amount)))) {
            revert InvalidProof();
        }

        hasClaimed[recipient] = true;
        seam.safeTransfer(recipient, amount);

        emit Claim(recipient, amount);
    }
}
