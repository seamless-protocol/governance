// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ERC20BalanceSplitterTwoPayee
/// @notice A contract that splits ERC20 token balances between two payees according to predefined shares
/// @dev Uses basis points (1/10000) for share calculations
contract ERC20BalanceSplitterTwoPayee {
    /// @dev Basis points scale used for share calculations (10000 = 100%)
    uint256 public constant _BASIS_POINT_SCALE = 1e4;

    /// @notice The first payee's address
    address public immutable payeeA;
    /// @notice The second payee's address
    address public immutable payeeB;
    /// @notice The ERC20 token to be split
    IERC20 public immutable token;
    /// @notice The share of payeeA in basis points (1/10000)
    uint256 public immutable shareA;

    error InvalidShare(uint256 share);
    error ZeroAddress();
    error InvalidToken();
    error SameAddresses();

    /// @notice Constructs the splitter contract
    /// @param payeeA_ Address of the first payee
    /// @param payeeB_ Address of the second payee
    /// @param token_ The ERC20 token contract to be split
    /// @param shareA_ The share of payeeA in basis points (1/10000)
    constructor(address payeeA_, address payeeB_, IERC20 token_, uint256 shareA_) {
        if (shareA_ > _BASIS_POINT_SCALE) revert InvalidShare(shareA_);
        if (payeeA_ == address(0) || payeeB_ == address(0)) revert ZeroAddress();
        if (address(token_) == address(0)) revert InvalidToken();
        if (payeeA_ == payeeB_) revert SameAddresses();

        payeeA = payeeA_;
        payeeB = payeeB_;
        token = token_;
        shareA = shareA_;
    }

    /// @notice Claims and splits the contract's token balance between the two payees
    /// @dev Calculates amounts based on shareA and transfers tokens to both payees
    function claim() external {
        uint256 totalAmount = token.balanceOf(address(this));

        uint256 amountToA = totalAmount * shareA / _BASIS_POINT_SCALE;
        uint256 amountToB = totalAmount * (_BASIS_POINT_SCALE - shareA) / _BASIS_POINT_SCALE;

        SafeERC20.safeTransfer(token, payeeA, amountToA);
        SafeERC20.safeTransfer(token, payeeB, amountToB);
    }

    /// @notice Transfers any other ERC20 token's full balance to payeeA
    /// @param token_ The ERC20 token to transfer
    /// @dev Used to recover tokens accidentally sent to the contract
    function skim(IERC20 token_) external {
        if (address(token_) == address(0)) revert InvalidToken();
        if (address(token_) == address(token)) revert InvalidToken();

        uint256 amount = token_.balanceOf(address(this));

        SafeERC20.safeTransfer(token_, payeeA, amount);
    }
}
