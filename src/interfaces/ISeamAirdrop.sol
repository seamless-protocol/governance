// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title Seam Airdrop Interface
/// @notice Interface for the Seam Airdrop contract
interface ISeamAirdrop {
    event MerkleRootSet(bytes32 merkleRoot);
    event Claim(address indexed recipient, uint256 amount);
    event ClaimAndVest(address indexed recipient, uint256 amount);

    error AlreadyClaimed(address recipient);
    error InvalidProof();

    /// @notice Changes merkle root
    /// @param _merkleRoot New merkle root
    /// @custom:usage Should be used only in cases merkle root is not generated properly or some addresses need to be included/excluded
    function setMerkleRoot(bytes32 _merkleRoot) external;

    /// @notice Claims tokens for the recipient
    /// @dev If proof is invalid or recipient already claimed tokens, reverts, otherwise tokens are sent to the recipient
    /// @param recipient Address to claim tokens for
    /// @param amount Amount of tokens to claim
    /// @param merkleProof Merkle proof
    function claim(address recipient, uint256 amount, bytes32[] calldata merkleProof) external;

    /// @notice Claims tokens for the recipient and vests them on escrow seam contract
    /// @dev If proof is invalid or recipient already claimed tokens, reverts, otherwise tokens are vested on behalf of caller
    /// @param amount Amount of tokens to claim and vest
    /// @param merkleProof Merkle proof
    function claimAndVest(uint256 amount, bytes32[] calldata merkleProof) external;
}
