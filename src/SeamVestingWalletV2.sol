// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotes} from "openzeppelin-contracts/governance/utils/IVotes.sol";
import {ISeamVestingWalletV2} from "./interfaces/ISeamVestingWalletV2.sol";
import {SeamVestingWalletV2Storage} from "./storage/SeamVestingWalletV2Storage.sol";
import {StakedToken} from "./StakedToken.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";

/// @title SeamVestingWalletV2
/// @author Seamless Protocol
/// @notice Enhanced vesting wallet contract that holds SEAM tokens with additional features
/// @dev VestingWallet implementation with cliff, lockup period, and staking functionality
contract SeamVestingWalletV2 is
    ISeamVestingWalletV2,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    SeamVestingWalletV2Storage
{
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

    /// @dev Initializes the vesting and inherited contracts
    /// @param _initialOwner address that controls vesting
    /// @param _beneficiary address that receives vested tokens
    /// @param _token ERC20 token that is being vested
    /// @param _stakedToken stkToken address
    /// @param _vestingStart timestamp when vesting starts
    /// @param _vestingDuration how long to vest tokens in seconds
    /// @param _vestingCliff cliff period in seconds before vesting begins
    function initialize(
        address _initialOwner,
        address _beneficiary,
        IERC20 _token,
        StakedToken _stakedToken,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _vestingCliff
    ) external initializer {
        if (_vestingCliff > _vestingDuration) revert InvalidCliff();

        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        StorageLayout storage $ = _getStorage();
        $.beneficiary = _beneficiary;
        $.token = _token;
        $.stakedToken = _stakedToken;
        $.vestingStart = _vestingStart;
        $.vestingDuration = _vestingDuration;
        $.vestingCliff = _vestingCliff;

        emit VestingWalletInitialized(
            address(_token), _beneficiary, address(_stakedToken), _vestingStart, _vestingDuration, _vestingCliff
        );
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @inheritdoc ISeamVestingWalletV2
    function beneficiary() public view returns (address) {
        return _getStorage().beneficiary;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function vestingStart() public view returns (uint256) {
        return _getStorage().vestingStart;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function vestingDuration() public view returns (uint256) {
        return _getStorage().vestingDuration;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function vestingCliff() public view returns (uint256) {
        return _getStorage().vestingCliff;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function vestingEnd() public view returns (uint256) {
        StorageLayout storage $ = _getStorage();
        uint256 vestingStart_ = $.vestingStart;

        if (vestingStart_ == 0) return type(uint64).max;

        return vestingStart_ + $.vestingDuration;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function released() public view returns (uint256) {
        return _getStorage().released;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function releasable() public view returns (uint256) {
        StorageLayout storage $ = _getStorage();

        // Return 0 during lockup window
        if (block.timestamp <= $.lockupEnd) {
            return 0;
        }

        uint256 currentVestedAmount = vestedAmount(uint64(block.timestamp));
        uint256 currentReleased = $.released;
        uint256 currentStakedAmount = $.stakedAmount;

        if (currentVestedAmount < (currentReleased + currentStakedAmount)) {
            return 0;
        }

        return currentVestedAmount - (currentReleased + currentStakedAmount);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        StorageLayout storage $ = _getStorage();
        uint256 totalAllocation = $.token.balanceOf(address(this)) + $.released + $.stakedAmount;

        // cache vestingStart to save gas
        uint256 currentVestingStart = $.vestingStart;

        if (currentVestingStart == 0 || timestamp < currentVestingStart + $.vestingCliff) {
            return 0;
        } else if (timestamp >= vestingEnd()) {
            return totalAllocation;
        } else {
            return Math.mulDiv(totalAllocation, timestamp - currentVestingStart, $.vestingDuration);
        }
    }

    /// @inheritdoc ISeamVestingWalletV2
    function lockupEnd() public view returns (uint256) {
        return _getStorage().lockupEnd;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function stakedAmount() public view returns (uint256) {
        return _getStorage().stakedAmount;
    }

    /// @inheritdoc ISeamVestingWalletV2
    function setVestingStart(uint64 startTimestamp) external onlyOwner {
        _getStorage().vestingStart = startTimestamp;
        emit VestingStartSet(startTimestamp);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function setVestingDuration(uint64 durationSeconds) external onlyOwner {
        StorageLayout storage $ = _getStorage();
        if ($.vestingCliff > durationSeconds) revert InvalidDuration();
        $.vestingDuration = durationSeconds;
        emit VestingDurationSet(durationSeconds);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function setVestingCliff(uint64 cliffSeconds) external onlyOwner {
        StorageLayout storage $ = _getStorage();
        if (cliffSeconds > $.vestingDuration) revert InvalidCliff();
        $.vestingCliff = cliffSeconds;
        emit VestingCliffSet(cliffSeconds);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function setLockupEnd(uint64 endTimestamp) external onlyOwner {
        StorageLayout storage $ = _getStorage();
        $.lockupEnd = endTimestamp;
        emit LockupEndSet(endTimestamp);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function setBeneficiary(address newBeneficiary) external onlyOwner {
        StorageLayout storage $ = _getStorage();
        address oldBeneficiary = $.beneficiary;
        $.beneficiary = newBeneficiary;
        emit BeneficiaryChanged(oldBeneficiary, newBeneficiary);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function setReleased(uint256 amount) external onlyOwner {
        StorageLayout storage $ = _getStorage();
        uint256 oldReleased = $.released;
        $.released = amount;
        emit ReleasedSet(oldReleased, amount);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function release() public {
        uint256 amount = releasable();

        StorageLayout storage $ = _getStorage();

        $.released += amount;
        SafeERC20.safeTransfer($.token, $.beneficiary, amount);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function delegate(address token, address delegatee) external onlyBeneficiary {
        StorageLayout storage $ = _getStorage();
        if (token != address($.token) && token != address($.stakedToken)) {
            revert InvalidToken();
        }
        IVotes(token).delegate(delegatee);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function stake(uint256 amount) external onlyBeneficiary {
        StorageLayout storage $ = _getStorage();

        // Check if we have enough vested tokens
        uint256 currentVestedAmount = vestedAmount(uint64(block.timestamp));
        uint256 availableToStake = 0;
        if (currentVestedAmount > ($.released + $.stakedAmount)) {
            availableToStake = currentVestedAmount - ($.released + $.stakedAmount);
        }

        // If amount is max, stake all available tokens
        if (amount == type(uint256).max) {
            amount = availableToStake;
        }

        if (amount > availableToStake) {
            revert InsufficientVestedTokens(amount, availableToStake);
        }

        // We track this amount separately from balanceOf stakedToken to handle slashing case
        $.stakedAmount += amount;

        // Approve and stake tokens
        $.token.approve(address($.stakedToken), amount);
        $.stakedToken.deposit(amount, address(this));
    }

    /// @inheritdoc ISeamVestingWalletV2
    function cooldown() external onlyBeneficiary {
        _getStorage().stakedToken.cooldown();
    }

    /// @inheritdoc ISeamVestingWalletV2
    function unstake(uint256 amount) external onlyBeneficiary {
        StorageLayout storage $ = _getStorage();

        // Perform unstake
        uint256 assets = $.stakedToken.redeem(amount, address(this), address(this));

        if (assets > $.stakedAmount) {
            $.stakedAmount = 0;
        } else {
            $.stakedAmount -= assets;
        }
    }

    /// @inheritdoc ISeamVestingWalletV2
    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        onlyBeneficiary
    {
        _getStorage().stakedToken.getRewardsController().claimRewards(assets, amount, to, reward);
    }

    function claimAllStakedRewards(address to) external onlyBeneficiary {
        StorageLayout storage $ = _getStorage();
        address[] memory assets = new address[](1);
        assets[0] = address($.stakedToken);
        $.stakedToken.getRewardsController().claimAllRewards(assets, to);
    }

    /// @inheritdoc ISeamVestingWalletV2
    function transfer(address token, address to, uint256 amount) external onlyOwner {
        SafeERC20.safeTransfer(IERC20(token), to, amount);
    }
}
