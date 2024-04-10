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
import {ISeamVestingWallet} from "src/interfaces/ISeamVestingWallet.sol";
import {SeamVestingWalletStorage as Storage} from "src/storage/SeamVestingWalletStorage.sol";

/// @title SeamVestingWallet
/// @author Seamless Protocol
/// @notice Vesting wallet contract that holds SEAM tokens and releases them to the beneficiary.
/// @dev VestingWallet implementation, modified from @openzeppelin implementation (https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/625fb3c2b2696f1747ba2e72d1e1113066e6c177/contracts/finance/VestingWalletUpgradeable.sol)
/// Changes are:
/// - beneficiary can claim vested ERC20 tokens, beneficiary cannot be transfered
/// - owner can upgrade contract, set vesting start time after deployment, withdraw tokens
/// - remove ETH vesting logic, only vest a single ERC20 token
contract SeamVestingWallet is ISeamVestingWallet, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary()) {
            revert NotBeneficiary(msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the vesting and inherited contracts.
    /// @param _initialOwner address that controls vesting
    /// @param _beneficiary address that receives vested tokens
    /// @param _token ERC20 token that is being vested
    /// @param _durationSeconds how long to vest tokens in seconds
    function initialize(address _initialOwner, address _beneficiary, IERC20 _token, uint64 _durationSeconds)
        external
        initializer
    {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        Storage.Layout storage $ = Storage.layout();
        $.beneficiary = _beneficiary;
        $.token = _token;
        $.duration = _durationSeconds;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @inheritdoc ISeamVestingWallet
    function beneficiary() public view returns (address) {
        return Storage.layout().beneficiary;
    }

    /// @inheritdoc ISeamVestingWallet
    function start() public view returns (uint256) {
        return Storage.layout().start;
    }

    /// @inheritdoc ISeamVestingWallet
    function setStart(uint64 startTimestamp) external onlyOwner {
        Storage.layout().start = startTimestamp;
    }

    /// @inheritdoc ISeamVestingWallet
    function duration() public view returns (uint256) {
        return Storage.layout().duration;
    }

    /// @inheritdoc ISeamVestingWallet
    function setDuration(uint64 _duration) external onlyOwner {
        Storage.layout().duration = _duration;
    }

    /// @inheritdoc ISeamVestingWallet
    function end() public view returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        uint256 start_ = $.start;

        if (start_ == 0) return type(uint64).max;

        return start_ + $.duration;
    }

    /// @inheritdoc ISeamVestingWallet
    function released() public view returns (uint256) {
        return Storage.layout().released;
    }

    /// @inheritdoc ISeamVestingWallet
    function releasable() public view returns (uint256) {
        uint256 vestedAmount_ = vestedAmount(uint64(block.timestamp));
        uint256 released_ = released();

        if (vestedAmount_ < released_) return 0;

        return vestedAmount_ - released_;
    }

    /// @inheritdoc ISeamVestingWallet
    function release() public {
        Storage.Layout storage $ = Storage.layout();

        uint256 amount = releasable();
        $.released += amount;
        emit ERC20Released(address($.token), amount);
        SafeERC20.safeTransfer($.token, $.beneficiary, amount);
    }

    /// @inheritdoc ISeamVestingWallet
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        uint256 totalAllocation = $.token.balanceOf(address(this)) + $.released;

        if ($.start == 0 || timestamp < $.start) {
            return 0;
        } else if (timestamp >= end()) {
            return totalAllocation;
        } else {
            return Math.mulDiv(totalAllocation, timestamp - $.start, $.duration);
        }
    }

    /// @inheritdoc ISeamVestingWallet
    function delegate(address delegatee) external onlyBeneficiary {
        IVotes(address(Storage.layout().token)).delegate(delegatee);
    }

    /// @inheritdoc ISeamVestingWallet
    function transfer(address token, address to, uint256 amount) external onlyOwner {
        SafeERC20.safeTransfer(IERC20(token), to, amount);
    }
}
