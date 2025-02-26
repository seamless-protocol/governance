// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IFeeSource} from "../../src/interfaces/IFeeSource.sol";

contract MockFeeSource is IFeeSource {
    IERC20 public immutable rewardToken;
    uint256 public claimableAmount;

    constructor(address _token) {
        rewardToken = IERC20(_token);
    }

    function setClaimableAmount(uint256 amount) external {
        claimableAmount = amount;
    }

    function claim() external override {
        if (claimableAmount > 0) {
            rewardToken.transfer(msg.sender, claimableAmount);
            claimableAmount = 0;
        }
    }

    function token() external view override returns (IERC20) {
        return rewardToken;
    }
}
