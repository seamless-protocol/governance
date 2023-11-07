// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (finance/VestingWallet.sol)
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";

/**
 * @dev VestingWallet implementation, modified from @openzeppelin implementation
 * Changes are:
 * - beneficiary can claim vested ERC20 tokens, beneficiary cannot be transfered
 * - owner can upgrade contract, set vesting start time after deployment, withdraw tokens
 * - remove ETH vesting logic, only vest a single ERC20 token
 */
contract SeamVestingWallet is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    event ERC20Released(address indexed token, uint256 amount);

    error NotBeneficiary(address account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @custom:storage-location erc7201:seamless.contracts.storage.SeamVestingWallet
    struct SeamVestingWalletStorage {
        address _beneficiary;
        IERC20 _token;
        uint256 _released;
        uint64 _start;
        uint64 _duration;
    }

    // keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.SeamVestingWallet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SeamVestingWalletStorageLocation =
        0x2657d9382d871507f053a87fb7cd637b396d29844abea995422d92ff6662dd00;

    function _getSeamVestingWalletStorage() private pure returns (SeamVestingWalletStorage storage $) {
        assembly {
            $.slot := SeamVestingWalletStorageLocation
        }
    }

    /// @param initialOwner address that controls vesting
    /// @param beneficiary_ address that receives vested tokens
    /// @param token ERC20 token that is being vested
    /// @param durationSeconds how long to vest tokens in seconds
    function initialize(address initialOwner, address beneficiary_, IERC20 token, uint64 durationSeconds)
        external
        initializer
    {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        $._beneficiary = beneficiary_;
        $._token = token;
        $._duration = durationSeconds;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev Getter for the beneficiary address.
     */
    function beneficiary() external view returns (address) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        return $._beneficiary;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start() public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        return $._start;
    }

    /// @param startTimestamp the new vesting start
    function setStart(uint64 startTimestamp) external onlyOwner {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        $._start = startTimestamp;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration() public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        return $._duration;
    }

    /**
     * @dev Getter for the end timestamp.
     */
    function end() public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        uint256 start_ = $._start;

        if (start_ == 0) return type(uint64).max;

        return start_ + $._duration;
    }

    /**
     * @dev Amount of token already released
     */
    function released() public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        return $._released;
    }

    /**
     * @dev Getter for the amount of releasable `token` tokens
     */
    function releasable() public view virtual returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released();
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ERC20Released} event.
     */
    function release() public virtual {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();

        uint256 amount = releasable();
        $._released += amount;
        emit ERC20Released(address($._token), amount);
        SafeERC20.safeTransfer($._token, $._beneficiary, amount);
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Using a linear vesting curve.
     */
    function vestedAmount(uint64 timestamp) public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        uint256 totalAllocation = $._token.balanceOf(address(this)) + $._released;
        if ($._start == 0 || timestamp < $._start) {
            return 0;
        } else if (timestamp >= end()) {
            return totalAllocation;
        } else {
            return Math.mulDiv(totalAllocation, timestamp - $._start, $._duration);
        }
    }

    /// @notice Delegate votes to target address
    function delegate(address delegatee) external {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();

        if (msg.sender != $._beneficiary) revert NotBeneficiary(msg.sender);

        IVotes(address($._token)).delegate(delegatee);
    }

    function withdraw(uint256 amount) external onlyOwner {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        $._token.transfer(msg.sender, amount);
    }
}
