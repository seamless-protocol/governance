// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title Airdrop Interface
/// @notice Interface for the Airdrop contract
interface IAirdrop {
    event MerkleRootSet(bytes32 merkleRoot);
    event Claim(address indexed recipient, uint256 amount);
    event Withdraw(address indexed recipient, uint256 amount);

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
    function claim(
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external;

    /// @notice Withdraws tokens from the contract
    /// @dev This function should be used only by the owner
    /// @param recipient Address to withdraw tokens to
    /// @param amount Amount of tokens to withdraw
    function withdraw(address recipient, uint256 amount) external;
}
