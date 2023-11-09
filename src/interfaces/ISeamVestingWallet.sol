// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ISeamVestingWallet {
    event ERC20Released(address indexed token, uint256 amount);

    error NotBeneficiary(address account);

    /// @notice Getter for the beneficiary address.
    function beneficiary() external view returns (address);

    /// @notice Getter for the start timestamp.
    function start() external view returns (uint256);

    /// @notice Change the vesting start date. Only callable by owner.
    /// @param startTimestamp the new vesting start
    function setStart(uint64 startTimestamp) external;

    /// @notice Getter for the vesting duration.
    function duration() external view returns (uint256);

    /// @notice Getter for the end timestamp.
    function end() external view returns (uint256);

    /// @notice Amount of token already released.
    function released() external view returns (uint256);

    /// @notice Getter for the amount of releasable `token` tokens
    function releasable() external view returns (uint256);

    /// @notice Release the tokens to the beneficiary that have already vested.
    /// @dev Emits a {ERC20Released} event.
    function release() external;

    /// @notice Calculates the amount of tokens that has already vested. Using a linear vesting curve.
    /// Any assets transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
    /// Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
    /// be immediately releasable.
    /// @param timestamp timestamp at which to return the vested amount
    function vestedAmount(uint64 timestamp) external view returns (uint256);

    /// @notice Delegate votes to target address. Only callable by beneficiary.
    /// @param delegatee address to delegate too
    function delegate(address delegatee) external;

    /// @notice Transfer tokens out of vesting contract. Only callable by owner
    /// @param token token to transfer out
    /// @param to address to send tokens to
    /// @param amount amount of tokens to transfer
    /// @dev Any assets transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
    /// Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
    /// be immediately releasable.
    function transfer(address token, address to, uint256 amount) external;
}
