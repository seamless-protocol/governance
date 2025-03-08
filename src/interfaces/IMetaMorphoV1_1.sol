// SPDX-License-Identifier: GPL-2.0-or-later
// Copied from https://github.com/morpho-org/metamorpho-v1.1/blob/d7ec9db0e987dbfb1b8a204dffc4cc4b9419ec86/src/interfaces/IMetaMorphoV1_1.sol
pragma solidity >=0.5.0;

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IMulticall {
    function multicall(bytes[] calldata) external returns (bytes[] memory);
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address) external;
    function renounceOwnership() external;
    function acceptOwnership() external;
    function pendingOwner() external view returns (address);
}

/// @dev This interface is used for factorizing IMetaMorphoV1_1StaticTyping and IMetaMorphoV1_1.
/// @dev Consider using the IMetaMorphoV1_1 interface instead of this one.
interface IMetaMorphoV1_1Base {
    /// @notice The address of the Morpho contract.
    function MORPHO() external view returns (address);
    function DECIMALS_OFFSET() external view returns (uint8);

    /// @notice The address of the curator.
    function curator() external view returns (address);

    /// @notice Stores whether an address is an allocator or not.
    function isAllocator(address target) external view returns (bool);

    /// @notice The current guardian. Can be set even without the timelock set.
    function guardian() external view returns (address);

    /// @notice The current fee.
    function fee() external view returns (uint96);

    /// @notice The fee recipient.
    function feeRecipient() external view returns (address);

    /// @notice The skim recipient.
    function skimRecipient() external view returns (address);

    /// @notice The current timelock.
    function timelock() external view returns (uint256);

    /// @notice Returns the length of the supply queue.
    function supplyQueueLength() external view returns (uint256);

    /// @notice Returns the length of the withdraw queue.
    function withdrawQueueLength() external view returns (uint256);

    /// @notice Stores the total assets managed by this vault when the fee was last accrued.
    function lastTotalAssets() external view returns (uint256);

    /// @notice Stores the missing assets due to realized bad debt or forced market removal.
    /// @dev In order to cover those lost assets, it is advised to supply on behalf of address(1) on the vault
    /// (canonical method).
    function lostAssets() external view returns (uint256);

    /// @notice Submits a `newTimelock`.
    /// @dev Warning: Reverts if a timelock is already pending. Revoke the pending timelock to overwrite it.
    /// @dev In case the new timelock is higher than the current one, the timelock is set immediately.
    function submitTimelock(uint256 newTimelock) external;

    /// @notice Accepts the pending timelock.
    function acceptTimelock() external;

    /// @notice Revokes the pending timelock.
    /// @dev Does not revert if there is no pending timelock.
    function revokePendingTimelock() external;

    /// @notice Sets the name of the vault.
    function setName(string memory newName) external;

    /// @notice Sets the symbol of the vault.
    function setSymbol(string memory newSymbol) external;

    /// @notice Submits a `newGuardian`.
    /// @notice Warning: a malicious guardian could disrupt the vault's operation, and would have the power to revoke
    /// any pending guardian.
    /// @dev In case there is no guardian, the gardian is set immediately.
    /// @dev Warning: Submitting a gardian will overwrite the current pending gardian.
    function submitGuardian(address newGuardian) external;

    /// @notice Accepts the pending guardian.
    function acceptGuardian() external;

    /// @notice Revokes the pending guardian.
    function revokePendingGuardian() external;

    /// @notice Skims the vault `token` balance to `skimRecipient`.
    function skim(address) external;

    /// @notice Sets `newAllocator` as an allocator or not (`newIsAllocator`).
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    /// @notice Sets `curator` to `newCurator`.
    function setCurator(address newCurator) external;

    /// @notice Sets the `fee` to `newFee`.
    function setFee(uint256 newFee) external;

    /// @notice Sets `feeRecipient` to `newFeeRecipient`.
    function setFeeRecipient(address newFeeRecipient) external;

    /// @notice Sets `skimRecipient` to `newSkimRecipient`.
    function setSkimRecipient(address newSkimRecipient) external;
}

/// @title IMetaMorphoV1_1
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @dev Use this interface for MetaMorphoV1_1 to have access to all the functions with the appropriate function
/// signatures.
interface IMetaMorphoV1_1 is IMetaMorphoV1_1Base, IERC4626, IERC20Permit, IOwnable, IMulticall {}
