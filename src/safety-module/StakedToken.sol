// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardsController} from "@aave/periphery-v3/contracts/rewards/interfaces/IRewardsController.sol";
import {IStakedToken} from "../interfaces/IStakedToken.sol";
import {StakedTokenStorage as Storage} from "../storage/StakedTokenStorage.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {NoncesUpgradeable} from "openzeppelin-contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {ERC4626Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";

contract StakedToken is
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    PausableUpgradeable, 
    IStakedToken
{
    using SafeERC20 for IERC20;

    bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    modifier isNotZeroAddress(address target) {
        if (target == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    /// @param _asset token address of the asset
    /// @param initialAdmin Initial admin of the contract
    /// @param _erc20name name of the share token
    /// @param _erc20symbol symbol of the share token
    function initialize(
        address _asset,
        address initialAdmin,
        string calldata _erc20name,
        string calldata _erc20symbol,
        uint256 _cooldown,
        uint256 unstake
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ERC20_init(_erc20name, _erc20symbol);
        __ERC4626_init(IERC20(_asset));

        __Pausable_init();

        Storage.Layout storage $ = Storage.layout();
        $.COOLDOWN_SECONDS = _cooldown;
        $.UNSTAKE_WINDOW = unstake;

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function scaledTotalSupply() external view returns (uint256) {
        return totalSupply();
    }

    function getScaledUserBalanceAndSupply(address user)
        external
        view
        returns (uint256, uint256)
    {
        return (balanceOf(user), totalSupply());
    }

    // Emergency functions
    function enableEmergencyWithdrawalState() external override onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
        emit EmergencyActive(true);
    }

    function endEmergencyWithdrawalState() external override onlyRole(PAUSER_ROLE) whenPaused {
        _unpause();
        emit EmergencyActive(false);
    }

    function emergencyWithdrawal(address to, uint256 amt) external override onlyRole(MANAGER_ROLE) {
        bool success = IERC20(asset()).transfer(to, amt);
        if (!success) revert SendFailed();
        emit EmergencyWithdraw(to, amt);
    }

    // Cooldown

    /**
     * @dev Begins the cooldown period to unstake
     * @notice Requires an active stake to activate
     *
     */
    function cooldown() external override {
        if (balanceOf(msg.sender) == 0) revert InsufficientStake();
        Storage.Layout storage $ = Storage.layout();
        $.stakersCooldowns[msg.sender] = block.timestamp;

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
     *
     */
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) public view override returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        uint256 toCooldownTimestamp = $.stakersCooldowns[toAddress];
        if (toCooldownTimestamp == 0) {
            return 0;
        }

        uint256 minimalValidCooldownTimestamp = block.timestamp - $.COOLDOWN_SECONDS - $.UNSTAKE_WINDOW;

        if (minimalValidCooldownTimestamp > toCooldownTimestamp) {
            toCooldownTimestamp = 0;
        } else {
            uint256 fromCooldownTimestampFinal =
                (minimalValidCooldownTimestamp > fromCooldownTimestamp) ? block.timestamp : fromCooldownTimestamp;

            if (fromCooldownTimestampFinal < toCooldownTimestamp) {
                return toCooldownTimestamp;
            } else {
                toCooldownTimestamp = (amountToReceive * fromCooldownTimestampFinal + (toBalance * toCooldownTimestamp))
                    / (amountToReceive + toBalance);
            }
        }
        // $.stakersCooldowns[toAddress] = toCooldownTimestamp;

        return toCooldownTimestamp;
    }
    // override _withdraw to check for cooldown
    // @notice block withdrawals when contract is paused aka in emergency state

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        whenNotPaused
    {
        Storage.Layout storage $ = Storage.layout();
        uint256 cooldownStartTimestamp = $.stakersCooldowns[owner];
        bool isValid = _checkCooldown(cooldownStartTimestamp, $.COOLDOWN_SECONDS, $.UNSTAKE_WINDOW);
        if (!isValid) revert CooldownActive();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    // override _deposit to revert if contract is paused
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
        whenNotPaused
    {
        super._deposit(caller, receiver, assets, shares);
    }

    function _checkCooldown(uint256 cd, uint256 COOLDOWN_SECONDS, uint256 UNSTAKE_WINDOW)
        internal
        view
        returns (bool)
    {
        if (cd == 0) return false;

        uint256 cooldownEnd = cd + COOLDOWN_SECONDS;
        if (block.timestamp <= cooldownEnd) {
            return false;
        }

        uint256 window = block.timestamp - cooldownEnd;
        if (window > UNSTAKE_WINDOW) {
            return false;
        }
        return true;
    }

    function decimals() public view virtual override(ERC20Upgradeable, ERC4626Upgradeable, IStakedToken) returns (uint8) {
        return super.decimals();
    }

    function nonces(address owner)
        public
        view
        virtual
        override(ERC20PermitUpgradeable, NoncesUpgradeable, IStakedToken)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    // _update override
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        Storage.Layout storage $ = Storage.layout();
        // save to local for gas efficiency
        // Can remove if we block any transfer during CD
        uint256 balFrom = balanceOf(from);
        uint256 balTo = balanceOf(to);
        if (from != address(0)) {
            _handleAction(from, totalSupply(), balFrom, $.rewardsController);
        }

        if (to != address(0) && to != from) {
            _handleAction(to, totalSupply(), balTo, $.rewardsController);
        }

        // Recipient
        if (from != to) {
            uint256 previousSenderCooldown = $.stakersCooldowns[from];
            $.stakersCooldowns[to] = getNextCooldownTimestamp(previousSenderCooldown, value, to, balTo);
            // if cooldown was set and whole balance of sender was transferred - clear cooldown
            if (balFrom == value && previousSenderCooldown != 0) {
                $.stakersCooldowns[from] = 0;
            }
        }

        super._update(from, to, value);
    }

    function _handleAction(
        address user,
        uint256 totalSupply,
        uint256 oldUserBalance,
        IRewardsController rewardsController
    ) internal {
        rewardsController.handleAction(user, totalSupply, oldUserBalance);
    }

    // Admin Functions
    function changeController(address newController) external override isNotZeroAddress(newController) onlyRole(MANAGER_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        $.rewardsController = IRewardsController(newController);
        emit RewardsControllerChange(newController);
    }

    function changeTimers(uint256 _cooldown, uint256 _unstake) external override onlyRole(MANAGER_ROLE) {
        Storage.Layout storage $ = Storage.layout();
        $.COOLDOWN_SECONDS = _cooldown;
        $.UNSTAKE_WINDOW = _unstake;

        emit TimersUpdated(_cooldown, _unstake);
    }

    // Storage getters
    function getCooldown() external view override returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        return $.COOLDOWN_SECONDS;
    }

    function getUnstakeWindow() external view override returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        return $.UNSTAKE_WINDOW;
    }

    function getStakerCooldown(address user) external view override returns (uint256) {
        Storage.Layout storage $ = Storage.layout();
        return $.stakersCooldowns[user];
    }

    function getRewardsController() external view override returns (address) {
        Storage.Layout storage $ = Storage.layout();
        return address($.rewardsController);
    }
}
