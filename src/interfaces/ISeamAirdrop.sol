// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @title Seam Airdrop Interface
/// @notice Interface for the Seam Airdrop contract
interface ISeamAirdrop {
    /// @notice InvalidVestingPercentage: maximum vesting percentage is 10000
    error InvalidVestingPercentage();

    /// @notice AlreadyClaimed: recipient already claimed tokens
    error AlreadyClaimed(address recipient);

    /// @notice InvalidProof: invalid merkle proof
    error InvalidProof();

    /// @notice Emitted when vesting percentage is set
    /// @param vestingPercentage Vesting percentage
    event VestingPercentageSet(uint256 vestingPercentage);

    /// @notice Emitted when merkle root is changed
    /// @param merkleRoot New merkle root
    event MerkleRootSet(bytes32 merkleRoot);

    /// @notice Emitted when tokens are claimed
    /// @param recipient Address that claimed tokens
    /// @param seamAmount Amount of SEAM tokens claimed
    /// @param esSeamAmount Amount of esSEAM tokens claimed
    event Claim(address indexed recipient, uint256 seamAmount, uint256 esSeamAmount);

    /// @notice Emitted when tokens are withdrawn
    /// @param token Address of the token withdrawn
    /// @param recipient Address that received tokens
    /// @param amount Amount of tokens withdrawn
    event Withdraw(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Sets the vesting percentage
    /// @param vestingPercentage Vesting percentage
    /// @dev Sets what percentage of total air-dropped SEAM tokens should be vested
    function setVestingPercentage(uint256 vestingPercentage) external;

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

    /// @notice Withdraws tokens from the contract
    /// @dev This function should be used only by the owner
    /// @param token Address of the token to withdraw
    /// @param recipient Address to withdraw tokens to
    /// @param amount Amount of tokens to withdraw
    function withdraw(IERC20 token, address recipient, uint256 amount) external;
}
