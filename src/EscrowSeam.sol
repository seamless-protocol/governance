// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IEscrowSeam} from "./interfaces/IEscrowSeam.sol";

/**
 * @title EscrowSeam
 * @author Seamless Protocol
 * @dev This contract is vesting contract for SEAM token.
 * @dev EscrowSeam token is not transferable.
 */
contract EscrowSeam is IEscrowSeam, ERC20Upgradeable, AccessControlUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.EscrowSeam")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EscrowSeamStorageLocation =
        0x6393c68bbda65a43373480543c4f1ff15eb61969ce223f59d8fd1889e26cc300;

    function _getEscrowSeamStorage() private pure returns (EscrowSeamStorage storage $) {
        assembly {
            $.slot := EscrowSeamStorageLocation
        }
    }

    /**
     * @notice Initializes the token storage and inherited contracts.
     * @param _seam SEAM token address
     * @param _vestingDuration Vesting duration
     */
    function initialize(address _seam, uint256 _vestingDuration, address _initialAdmin) public initializer {
        __ERC20_init("Escrow Seamless", "esSEAM");
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);

        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        $.seam = IERC20(_seam);
        $.vestingDuration = _vestingDuration;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @notice Prevents transfer of the token.
     */
    function transfer(address, uint256) public override(IERC20, ERC20Upgradeable) returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice Prevents transfer of the token.
     */
    function transferFrom(address, address, uint256) public override(IERC20, ERC20Upgradeable) returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice Returns the SEAM token address.
     */
    function seam() public view returns (address) {
        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        return address($.seam);
    }

    /**
     * @notice Returns the vesting duration.
     */
    function vestingDuration() public view returns (uint256) {
        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        return $.vestingDuration;
    }

    /**
     * @notice Returns the vesting info of the account.
     * @param account Account to query
     */
    function vestingInfo(address account) external view returns (uint256, uint256, uint256, uint256) {
        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        VestingData storage vestingData = $.vestingInfo[account];
        return (
            vestingData.claimableAmount,
            vestingData.unvestPerSecond,
            vestingData.vestingEndsAt,
            vestingData.lastUpdatedTimestamp
        );
    }

    /**
     * @notice Calculates and returns total claimable(unvested) amount of the account at the moment.
     * @dev This function should be used internally to calculate claimable amount and on frontend to display claimable amount.
     * @param account Account to query unvested amount for
     */
    function getClaimableAmount(address account) public view returns (uint256) {
        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        VestingData storage vestingData = $.vestingInfo[account];
        uint256 timeDiff = Math.min(block.timestamp, vestingData.vestingEndsAt) - vestingData.lastUpdatedTimestamp;
        uint256 unvestedAmount = timeDiff.mulDiv(vestingData.unvestPerSecond, 1e18);
        return vestingData.claimableAmount + unvestedAmount;
    }

    /**
     * @notice Vests SEAM token to the contract.
     * @dev This function should be user only by core protocol contracts. Contract should send SEAM tokens to this contract before calling deposit
     * @param account Account to vest for
     * @param amount Amount to vest
     */
    function deposit(address account, uint256 amount) external onlyRole(DEPOSITOR_ROLE) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        _updateVesting(account);

        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        VestingData storage vestingData = $.vestingInfo[account];

        uint256 timeUntilEnd = vestingData.vestingEndsAt - Math.min(block.timestamp, vestingData.vestingEndsAt);
        uint256 currVestingAmount = vestingData.unvestPerSecond.mulDiv(timeUntilEnd, 1e18);
        uint256 newVestingPeriodDuration =
            ((currVestingAmount * timeUntilEnd) + (amount * $.vestingDuration)) / (currVestingAmount + amount);

        vestingData.unvestPerSecond = (currVestingAmount + amount).mulDiv(1e18, newVestingPeriodDuration);
        vestingData.vestingEndsAt = block.timestamp + newVestingPeriodDuration;

        _mint(account, amount);
        emit Deposit(account, amount);
    }

    /**
     * @notice Claims unvested tokens.
     */
    function claim() external {
        _updateVesting(msg.sender);

        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        VestingData storage vestingData = $.vestingInfo[msg.sender];
        _burn(msg.sender, vestingData.claimableAmount);
        $.seam.safeTransfer(msg.sender, vestingData.claimableAmount);

        emit Claim(msg.sender, vestingData.claimableAmount);
        vestingData.claimableAmount = 0;
    }

    /**
     * @notice Updates the vesting info of the account.
     */
    function _updateVesting(address account) private {
        EscrowSeamStorage storage $ = _getEscrowSeamStorage();
        VestingData storage vestingData = $.vestingInfo[account];
        vestingData.claimableAmount = getClaimableAmount(account);
        vestingData.lastUpdatedTimestamp = block.timestamp;
    }
}
