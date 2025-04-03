// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SeamVestingWalletV2 Interface
/// @notice Interface for the enhanced Seam vesting Wallet contract
interface ISeamVestingWalletV2 {
    /// @notice NotBeneficiary: only beneficiary can claim tokens
    error NotBeneficiary(address account);

    /// @notice LockupActive: tokens cannot be claimed during lockup period
    error LockupActive();

    /// @notice NoStakedTokens: no tokens are currently staked
    error NoStakedTokens();

    /// @notice InvalidCliff: cliff must be less than or equal to duration
    error InvalidCliff();

    /// @notice CliffNotReached: vesting cliff period has not been reached
    error CliffNotReached();

    /// @notice InsufficientVestedTokens: not enough vested tokens available
    error InsufficientVestedTokens(uint256 requested, uint256 available);

    /// @notice InvalidToken: token is not SEAM or stkSEAM
    error InvalidToken();

    /// @notice InvalidDuration: duration must be greater than or equal to cliff
    error InvalidDuration();

    /// @notice VestingWalletInitialized: vesting wallet initialized
    /// @param token ERC20 token that is being vested
    /// @param beneficiary Address that will receive the vested tokens
    /// @param stakedToken Address of the staked token (stkSEAM)
    /// @param vestingStart Timestamp when vesting starts
    /// @param vestingDuration Duration of the vesting period in seconds
    /// @param vestingCliff Cliff period in seconds before vesting begins
    event VestingWalletInitialized(
        address indexed token,
        address indexed beneficiary,
        address stakedToken,
        uint64 vestingStart,
        uint64 vestingDuration,
        uint64 vestingCliff
    );

    /// @notice Emitted when beneficiary is changed
    /// @param oldBeneficiary Previous beneficiary address
    /// @param newBeneficiary New beneficiary address
    event BeneficiaryChanged(address indexed oldBeneficiary, address indexed newBeneficiary);

    /// @notice Emitted when vesting start is set
    /// @param startTimestamp New vesting start timestamp
    event VestingStartSet(uint64 startTimestamp);

    /// @notice Emitted when cliff duration is set
    /// @param cliff New cliff duration
    event VestingCliffSet(uint64 cliff);

    /// @notice Emitted when vesting duration is set
    /// @param duration New vesting duration
    event VestingDurationSet(uint64 duration);

    /// @notice Emitted when lockup period is set
    /// @param endTimestamp End of lockup period
    event LockupEndSet(uint64 endTimestamp);

    /// @notice Emitted when released amount is set
    /// @param oldReleased Previous released amount
    /// @param newReleased New released amount
    event ReleasedSet(uint256 oldReleased, uint256 newReleased);

    /// @notice Getter for the beneficiary address
    function beneficiary() external view returns (address);

    /// @notice Getter for the vesting start timestamp
    function vestingStart() external view returns (uint256);

    /// @notice Change the vesting start date. Only callable by owner
    /// @param startTimestamp the new vesting start
    function setVestingStart(uint64 startTimestamp) external;

    /// @notice Getter for the vesting duration
    function vestingDuration() external view returns (uint256);

    /// @notice Change the vesting duration. Only callable by owner
    /// @param duration_ the new vesting duration
    function setVestingDuration(uint64 duration_) external;

    /// @notice Getter for the vesting cliff duration
    function vestingCliff() external view returns (uint256);

    /// @notice Set the vesting cliff duration. Only callable by owner
    /// @param cliff_ the new vesting cliff duration
    function setVestingCliff(uint64 cliff_) external;

    /// @notice Getter for the vesting end timestamp
    function vestingEnd() external view returns (uint256);

    /// @notice Amount of token already released
    function released() external view returns (uint256);

    /// @notice Getter for the amount of releasable tokens
    function releasable() external view returns (uint256);

    /// @notice Change the released amount. Only callable by owner
    /// @param amount the new released amount
    function setReleased(uint256 amount) external;

    /// @notice Release the tokens to the beneficiary that have already vested. Staked tokens must be unstake before releasing.
    function release() external;

    /// @notice Calculates the amount of tokens that has already vested
    /// @param timestamp timestamp at which to return the vested amount
    function vestedAmount(uint64 timestamp) external view returns (uint256);

    /// @notice Delegate votes to target address. Only callable by beneficiary
    /// @param token Token to delegate votes for (SEAM or stkSEAM)
    /// @param delegatee address to delegate to
    function delegate(address token, address delegatee) external;

    /// @notice Transfer tokens out of vesting contract. Only callable by owner
    /// @param token token to transfer out
    /// @param to address to send tokens to
    /// @param amount amount of tokens to transfer
    function transfer(address token, address to, uint256 amount) external;

    /// @notice Get the lockup end timestamp
    function lockupEnd() external view returns (uint256);

    /// @notice Set the lockup period. Only callable by owner
    /// @param endTimestamp end of lockup period
    function setLockupEnd(uint64 endTimestamp) external;

    /// @notice Stake vested tokens. Only callable by beneficiary
    /// @param amount amount of tokens to stake, use type(uint256).max to stake all available
    function stake(uint256 amount) external;

    /// @notice Start cooldown period for unstaking. Only callable by beneficiary
    function cooldown() external;

    /// @notice Getter for the amount of staked tokens
    function stakedAmount() external view returns (uint256);

    /**
     * @notice Unstake tokens. Only callable by beneficiary
     * @param amount amount of tokens to unstake
     * @dev Call redeem() on staked token to unstake. If redeem results in less token returned than initially staked,
     * those tokens are effectively considered vested and released. If redeem results in more tokens returned than initially staked,
     * the excess is added to total allocation and will vest accordingly.
     */
    function unstake(uint256 amount) external;

    /// @notice Claim specific rewards from staking. Only callable by beneficiary
    /// @param assets Array of asset addresses to claim rewards for
    /// @param amount Amount of rewards to claim
    /// @param to Address to send rewards to
    /// @param reward Address of reward token to claim
    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward) external;

    /// @notice Claim all rewards from staked tokens. Only callable by beneficiary
    /// @param to Address to send rewards to
    function claimAllStakedRewards(address to) external;

    /// @notice Change the beneficiary address. Only callable by owner
    /// @param newBeneficiary new beneficiary address
    function setBeneficiary(address newBeneficiary) external;
}
