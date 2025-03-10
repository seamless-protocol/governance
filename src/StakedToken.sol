// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardsController} from "aave-v3-periphery/contracts/rewards/interfaces/IRewardsController.sol";
import {IStakedToken} from "./interfaces/IStakedToken.sol";
import {StakedTokenStorage} from "./storage/StakedTokenStorage.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {NoncesUpgradeable} from "openzeppelin-contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {ERC4626Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {VotesUpgradeable} from "openzeppelin-contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title StakedToken
 * @author Seamless Protocol
 * @notice Implementation of a staked token with cooldown period, governance capabilities, and rewards
 * @dev This contract implements ERC4626 for tokenized vault standard, ERC20Permit for gasless approvals,
 *      ERC20Votes for governance functionality, and includes cooldown/unstake mechanics for withdrawals.
 *      The contract is upgradeable, access-controlled, and pausable.
 *
 *      Users can stake tokens to receive shares, which represent ownership in the vault.
 *      Before withdrawing, users must initiate a cooldown period and withdraw within the unstake window.
 *      The contract supports delegation of voting power for governance purposes.
 */
contract StakedToken is
    IStakedToken,
    UUPSUpgradeable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    StakedTokenStorage
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    /// @param _asset token address of the asset
    /// @param _initialAdmin Initial admin of the contract
    /// @param _erc20name name of the share token
    /// @param _erc20symbol symbol of the share token
    function initialize(
        address _asset,
        address _initialAdmin,
        string calldata _erc20name,
        string calldata _erc20symbol,
        uint256 _cooldown,
        uint256 _unstakeWindow
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ERC20_init(_erc20name, _erc20symbol);
        __ERC4626_init(IERC20(_asset));
        __ERC20Permit_init(_erc20name);
        __ERC20Votes_init();
        __Pausable_init();

        StorageLayout storage $ = storageLayout();
        $.cooldownSeconds = _cooldown;
        $.unstakeWindow = _unstakeWindow;

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(MANAGER_ROLE, _initialAdmin);
        _grantRole(UPGRADER_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    /// @inheritdoc IStakedToken
    function scaledTotalSupply() external view returns (uint256 scaledSupply) {
        scaledSupply = totalSupply();
    }

    /// @inheritdoc IStakedToken
    function getScaledUserBalanceAndSupply(address user)
        external
        view
        returns (uint256 scaledBalance, uint256 scaledSupply)
    {
        scaledBalance = balanceOf(user);
        scaledSupply = totalSupply();
    }

    /// @inheritdoc IStakedToken
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IStakedToken
    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IStakedToken
    function emergencyWithdrawal(address to, uint256 amt) external override onlyRole(MANAGER_ROLE) {
        SafeERC20.safeTransfer(IERC20(asset()), to, amt);
        emit EmergencyWithdraw(to, amt);
    }

    /// @inheritdoc VotesUpgradeable
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @inheritdoc VotesUpgradeable
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // Cooldown
    /// @inheritdoc IStakedToken
    function cooldown() external override {
        if (balanceOf(msg.sender) == 0) revert InsufficientStake();
        storageLayout().stakersCooldowns[msg.sender] = block.timestamp;

        emit Cooldown(msg.sender);
    }

    /// @inheritdoc IStakedToken
    function getNextCooldownTimestamp(
        uint256 fromCooldownTimestamp,
        uint256 amountToReceive,
        address toAddress,
        uint256 toBalance
    ) public view override returns (uint256 cooldownTimestamp) {
        StorageLayout storage $ = storageLayout();
        uint256 toCooldownTimestamp = $.stakersCooldowns[toAddress];
        if (toCooldownTimestamp == 0) {
            return 0;
        }

        uint256 minimalValidCooldownTimestamp = block.timestamp - $.cooldownSeconds - $.unstakeWindow;

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

        cooldownTimestamp = toCooldownTimestamp;
    }

    /**
     * @dev override of ERC4626 Withdraw
     * @notice adds validate cooldown before withdraw and pausable
     * @param caller address of caller
     * @param receiver address to receive
     * @param owner token owner
     * @param assets amount of asset to withdraw
     * @param shares the amount of shares to burn
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        whenNotPaused
    {
        _validateCooldown(owner);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev override of ERC4626 deposit
     * @notice adds pausable
     * @param caller address of caller
     * @param receiver address to receive
     * @param assets amount of asset to deposit
     * @param shares the amount of shares to mint
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
        whenNotPaused
    {
        super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev ensures the user's cooldown has correctly elapsed
     * @param user address of user
     */
    function _validateCooldown(address user) internal view {
        uint256 cooldownStartTimestamp = getStakerCooldown(user);
        if (cooldownStartTimestamp == 0) revert CooldownNotInitiated();

        uint256 cooldownSeconds = getCooldown();
        uint256 unstakeWindow = getUnstakeWindow();
        uint256 cooldownEnd = cooldownStartTimestamp + cooldownSeconds;
        if (block.timestamp <= cooldownEnd) {
            revert CooldownStillActive();
        }

        uint256 window = block.timestamp - cooldownEnd;
        if (window > unstakeWindow) {
            revert UnstakeWindowExpired();
        }
    }

    /// @inheritdoc IStakedToken
    function decimals()
        public
        view
        virtual
        override(ERC20Upgradeable, ERC4626Upgradeable, IStakedToken)
        returns (uint8 decimal)
    {
        decimal = super.decimals();
    }

    /**
     * @dev See {IERC4626-maxDeposit}.
     */
    function maxDeposit(address) public view override returns (uint256) {
        return _maxSupply();
    }

    /**
     * @dev See {IERC4626-maxMint}.
     */
    function maxMint(address) public view override returns (uint256) {
        return _maxSupply();
    }

    /// @inheritdoc IStakedToken
    function nonces(address owner)
        public
        view
        virtual
        override(ERC20PermitUpgradeable, NoncesUpgradeable, IStakedToken)
        returns (uint256 nonce)
    {
        nonce = super.nonces(owner);
    }

    /**
     * @dev override of ERC20 update
     * @notice adds custom logic to transfers (handling action on reward controller)
     * @param from sending address
     * @param to receiving address
     * @param value amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        StorageLayout storage $ = storageLayout();
        // save to local for gas efficiency
        // Can remove if we block any transfer during CD
        uint256 balFrom = balanceOf(from);
        uint256 balTo = balanceOf(to);
        uint256 supply = totalSupply();
        if (from != address(0)) {
            _handleAction(from, supply, balFrom);
        }

        if (to != address(0) && to != from) {
            _handleAction(to, supply, balTo);
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

    /**
     * @dev triggers the reward controller to update reward indexes
     * @param user address of user
     * @param totalSupply supply of stakedToken
     * @param oldUserBalance previous balance of user
     */
    function _handleAction(address user, uint256 totalSupply, uint256 oldUserBalance) internal {
        if (address(getRewardsController()) == address(0)) {
            return;
        }
        getRewardsController().handleAction(user, totalSupply, oldUserBalance);
    }

    // Admin Functions
    /// @inheritdoc IStakedToken
    function setController(address newController) external override onlyRole(MANAGER_ROLE) {
        storageLayout().rewardsController = IRewardsController(newController);
        emit RewardsControllerSet(newController);
    }

    /// @inheritdoc IStakedToken
    function setTimers(uint256 _cooldown, uint256 _unstake) external override onlyRole(MANAGER_ROLE) {
        StorageLayout storage $ = storageLayout();
        $.cooldownSeconds = _cooldown;
        $.unstakeWindow = _unstake;

        emit TimersSet(_cooldown, _unstake);
    }

    // Storage getters
    /// @inheritdoc IStakedToken
    function getCooldown() public view override returns (uint256 cooldownTime) {
        cooldownTime = storageLayout().cooldownSeconds;
    }

    /// @inheritdoc IStakedToken
    function getUnstakeWindow() public view override returns (uint256 unstakeWindow) {
        unstakeWindow = storageLayout().unstakeWindow;
    }

    /// @inheritdoc IStakedToken
    function getStakerCooldown(address user) public view override returns (uint256 cooldownStartedAt) {
        cooldownStartedAt = storageLayout().stakersCooldowns[user];
    }

    /// @inheritdoc IStakedToken
    function getRewardsController() public view override returns (IRewardsController rewardController) {
        rewardController = storageLayout().rewardsController;
    }
}
