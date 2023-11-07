// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";

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

    function initialize(address initialOwner, address beneficiary, IERC20 token, uint64 durationSeconds)
        external
        initializer
    {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        $._beneficiary = beneficiary;
        $._token = token;
        $._duration = durationSeconds;
        $._start = type(uint64).max;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function start() public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        return $._start;
    }

    function setStart(uint64 startTimestamp) external onlyOwner {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        $._start = startTimestamp;
    }

    function duration() public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        return $._duration;
    }

    function end() public view virtual returns (uint256) {
        return start() + duration();
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
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(uint64 timestamp) public view virtual returns (uint256) {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        return _vestingSchedule($._token.balanceOf(address(this)) + released(), timestamp);
    }

    /// @notice Delegate votes to target address
    function delegate(address delegatee) external {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        if (msg.sender != $._beneficiary) revert NotBeneficiary(msg.sender);
        IVotes(address($._token)).delegate(delegatee);
    }

    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) internal view virtual returns (uint256) {
        if (start() == 0 || timestamp < start()) {
            return 0;
        } else if (timestamp >= end()) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start())) / duration();
        }
    }

    function withdraw(uint256 amount) external onlyOwner {
        SeamVestingWalletStorage storage $ = _getSeamVestingWalletStorage();
        $._token.transfer(msg.sender, amount);
    }
}
