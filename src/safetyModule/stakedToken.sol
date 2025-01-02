// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

contract StakedToken is UUPSUpgradeable, AccessControlUpgradeable, Initializable, ERC4626Upgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // errors
    error SendFailed();
    error isZeroAddress(address target);
    error InsufficientStake();
    error CooldownActive();

    // events
    event EmergencyActive(bool status);
    event EmergencyWithdraw(address to, uint256 amt);
    event RewardControllerChange(address RewardController);
    event Cooldown(address user);

    // Global State
    /// @dev role which can change strategy parameters
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    /// @dev role which can upgrade the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    IERC20 asset;

    bool isEmergencyWithdrawal;

    address RewardController;

    /// @notice Seconds to wait before unstake window is available
    uint256 public COOLDOWN_SECONDS;

    /// @notice Seconds available to redeem once the cooldown period is fullfilled
    uint256 public UNSTAKE_WINDOW;

    mapping(address => uint256) public stakersCooldowns;

    modifier isNotZeroAddress(address target) {
        if (target == address(0)) {
            revert isZeroAddress(target);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    /// @param seam SEAM token address
    /// @param emissionPerSecond Emission per second
    /// @param initialAdmin Initial admin of the contract
    function initialize(
        address _asset,
        address controller,
        address initialAdmin,
        string _erc20name, 
        string _erc20symbol
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ERC4626_init(_asset);
        __ERC20_init(_erc20name, _erc20symbol);
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
       
        asset = IERC20(_asset);
        RewardController = controller;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    { }

    // Emergency functions
    function enableEmergencyWithdrawalState() external onlyRole(MANAGER_ROLE) {
        _pause();
        isEmergencyWithdrawal = true;
        emit EmergencyActive(true);
    }

    function endEmergencyWithdrawalState() external onlyRole(MANAGER_ROLE) {
        _unpause();
        isEmergencyWithdrawal = false;
        emit EmergencyActive(false);
    }

    function emergencyWithdrawal(address to, uint256 amt) external onlyRole(MANAGER_ROLE) {
        bool success = asset.transfer(to, amt);
        if (!success) revert SendFailed();
        emit EmergencyWithdraw(to, amt);
    }

    // Cooldown

    /**
     * @dev Begins the cooldown period to unstake
     * @notice Requires an active stake to activate
     **/
    function cooldown() external override {
        if (balanceOf(msg.sender) == 0) revert InsufficientStake();
        stakersCooldowns[msg.sender] = block.timestamp;

        emit Cooldown(msg.sender);
    }

    /**
     * @dev Calculates the how is gonna be a new cooldown timestamp depending on the sender/receiver situation
     *  - If the timestamp of the sender is "better" or the timestamp of the recipient is 0, we take the one of the recipient
     *  - Weighted average of from/to cooldown timestamps if:
     *    # The sender doesn't have the cooldown activated (timestamp 0).
     *    # The sender timestamp is expired
     *    # The sender has a "worse" timestamp
     *  - If the receiver's cooldown timestamp expired (too old), the next is 0
     * @param fromCooldownTimestamp Cooldown timestamp of the sender
     * @param amountToReceive Amount
     * @param toAddress Address of the recipient
     * @param toBalance Current balance of the receiver
     * @return The new cooldown timestamp
     **/
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) public returns (uint256) {
        uint256 toCooldownTimestamp = stakersCooldowns[toAddress];
        if (toCooldownTimestamp == 0) {
            return 0;
        }

        uint256 minimalValidCooldownTimestamp = block.timestamp - COOLDOWN_SECONDS - UNSTAKE_WINDOW;

        if (minimalValidCooldownTimestamp > toCooldownTimestamp) {
            toCooldownTimestamp = 0;
        } else {
            uint256 fromCooldownTimestampFinal = (minimalValidCooldownTimestamp > fromCooldownTimestamp)
                ? block.timestamp
                : fromCooldownTimestamp;

            if (fromCooldownTimestampFinal < toCooldownTimestamp) {
                return toCooldownTimestamp;
            } else {
                toCooldownTimestamp = (amountToReceive * fromCooldownTimestampFinal + (toBalance * toCooldownTimestamp))
                    / (amountToReceive + toBalance);
            }
        }
        stakersCooldowns[toAddress] = toCooldownTimestamp;

        return toCooldownTimestamp;
    }
    // override _withdraw to check for cooldown
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        uint256 cooldownStartTimestamp = stakersCooldowns[owner];
        bool isValid = _checkCooldown(cooldownStartTimestamp);
        if (!isValid) revert CooldownActive();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _checkCooldown(uint256 cd) internal returns(bool) {
        uint256 cooldownEnd = cd + COOLDOWN_SECONDS;
        if (block.timestamp > cooldownEnd) {
            return false;
        }

        uint256 window = block.timestamp - cooldownEnd;
        if (window <= UNSTAKE_WINDOW) {
            return false;
        }
        return true;
    }

    // _update override
    function _update(address from, address to, uint256 value)
        internal
        override
    {   
        // save to local for gas efficiency
        // Can remove if we block any transfer during CD
        uint256 balFrom = balanceOf(from);
        uint256 balTo = balanceOf(to);
        if (from != address(0)) {
            _handleAction(from, totalSupply(), balFrom);
        }

        if (to != address(0) && to != from) {
            _handleAction(to, totalSupply(), balTo);
        }

        // Recipient
        if (from != to) {
            uint256 previousSenderCooldown = stakersCooldowns[from];
            stakersCooldowns[to] = getNextCooldownTimestamp(previousSenderCooldown, amount, to, balTo);
            // if cooldown was set and whole balance of sender was transferred - clear cooldown
            if (balFrom == amount && previousSenderCooldown != 0) {
                stakersCooldowns[from] = 0;
            }
        }

        super._update(from, to, value);
    }

    function _handleAction(
        address user,
        uint256 totalSupply,
        uint256 oldUserBalance
    ) internal {
        IPoolAddressesProvider poolAddressProvider =
            Storage.layout().poolAddressProvider;

        IRewardsController rewardsController = IRewardsController(
            poolAddressProvider.getAddress(INCENTIVES_CONTROLLER)
        );

        if (address(rewardsController) != address(0)) {
            rewardsController.handleAction(user, totalSupply, oldUserBalance);
        }
    }

    // Admin Functions
    function changeController(address newController) external isNotZeroAddress(newController) onlyRole(MANAGER_ROLE) {
        RewardController = newController;
        emit RewardControllerChange(newController);
    }

}

// TODO: TEST: Mint and burn should trigger _update, so _deposit does not need to be modified
// TODO: override _withdraw to revert if CD present
// TODO: Add ERC20Votes