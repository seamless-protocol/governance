// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20VotesUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {VotesUpgradeable} from "openzeppelin-contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IEscrowSeam} from "./interfaces/IEscrowSeam.sol";
import {EscrowSeamStorage as Storage} from "./storage/EscrowSeamStorage.sol";

/// @title EscrowSeam
/// @author Seamless Protocol
/// @dev This contract is vesting contract for SEAM token.
/// @dev EscrowSeam token is not transferable.
contract EscrowSeam is IEscrowSeam, ERC20Upgradeable, ERC20VotesUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private constant MULTIPLIER = 1e18;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the token storage and inherited contracts.
    /// @param _seam SEAM token address
    /// @param _vestingDuration Vesting duration
    /// @param _initialOwner Initial owner of the contract
    function initialize(address _seam, uint256 _vestingDuration, address _initialOwner) public initializer {
        __ERC20_init("Escrow SEAM", "esSEAM");
        __ERC20Votes_init();
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        Storage.Layout storage $ = Storage.layout();
        $.seam = IERC20(_seam);
        $.vestingDuration = _vestingDuration;
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @inheritdoc VotesUpgradeable
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @inheritdoc VotesUpgradeable
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /// @notice Prevents transfer of the token.
    function transfer(address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert NonTransferable();
    }

    /// @notice Prevents transfer of the token.
    function transferFrom(address, address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert NonTransferable();
    }

    /// @inheritdoc IEscrowSeam
    function seam() public view returns (address) {
        return address(Storage.layout().seam);
    }

    /// @inheritdoc IEscrowSeam
    function vestingDuration() public view returns (uint256) {
        return Storage.layout().vestingDuration;
    }

    /// @inheritdoc IEscrowSeam
    function vestingInfo(address account) external view returns (uint256, uint256, uint256, uint256) {
        Storage.VestingData storage vestingData = Storage.layout().vestingInfo[account];
        return (
            vestingData.claimableAmount,
            vestingData.vestPerSecond,
            vestingData.vestingEndsAt,
            vestingData.lastUpdatedTimestamp
        );
    }

    /// @inheritdoc IEscrowSeam
    function getClaimableAmount(address account) public view returns (uint256) {
        Storage.VestingData storage vestingData = Storage.layout().vestingInfo[account];

        if (vestingData.lastUpdatedTimestamp > vestingData.vestingEndsAt) return vestingData.claimableAmount;

        uint256 timeDiff = Math.min(block.timestamp, vestingData.vestingEndsAt) - vestingData.lastUpdatedTimestamp;
        uint256 vestedAmount = Math.mulDiv(timeDiff, vestingData.vestPerSecond, MULTIPLIER);
        return vestingData.claimableAmount + vestedAmount;
    }

    /// @inheritdoc IEscrowSeam
    function deposit(address onBehalfOf, uint256 amount) external {
        if (amount == 0) {
            return;
        }

        _updateVesting(onBehalfOf);

        Storage.Layout storage $ = Storage.layout();
        Storage.VestingData storage vestingData = $.vestingInfo[onBehalfOf];

        uint256 timeUntilEnd = vestingData.vestingEndsAt - Math.min(block.timestamp, vestingData.vestingEndsAt);
        uint256 currVestingAmount = Math.mulDiv(vestingData.vestPerSecond, timeUntilEnd, MULTIPLIER);
        uint256 newVestingPeriodDuration =
            ((currVestingAmount * timeUntilEnd) + (amount * $.vestingDuration)) / (currVestingAmount + amount);

        vestingData.vestPerSecond = Math.mulDiv(currVestingAmount + amount, MULTIPLIER, newVestingPeriodDuration);
        vestingData.vestingEndsAt = block.timestamp + newVestingPeriodDuration;

        _mint(onBehalfOf, amount);
        SafeERC20.safeTransferFrom($.seam, msg.sender, address(this), amount);
        emit Deposit(msg.sender, onBehalfOf, amount);
    }

    /// @inheritdoc IEscrowSeam
    function claim(address account) external {
        _updateVesting(account);

        Storage.Layout storage $ = Storage.layout();
        Storage.VestingData storage vestingData = $.vestingInfo[account];
        _burn(account, vestingData.claimableAmount);
        SafeERC20.safeTransfer($.seam, account, vestingData.claimableAmount);

        emit Claim(account, vestingData.claimableAmount);
        vestingData.claimableAmount = 0;
    }

    /// @notice Updates vesting info for the given account. Calculates and updates claimable amount as well as last updated timestamp.
    /// @param account Account to update vesting info for
    function _updateVesting(address account) private {
        Storage.VestingData storage vestingData = Storage.layout().vestingInfo[account];
        vestingData.claimableAmount = getClaimableAmount(account);
        vestingData.lastUpdatedTimestamp = block.timestamp;
    }

    /// @inheritdoc ERC20Upgradeable
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, value);
    }
}
