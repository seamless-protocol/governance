// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IFeeSource} from "../../src/interfaces/IFeeSource.sol";

contract MockFeeSource is IFeeSource {
    IERC20 public _token;
    uint256 public _amount;
    bool public _shouldRevert;

    constructor(IERC20 token_) {
        _token = token_;
    }

    function token() external view override returns (IERC20) {
        return _token;
    }

    function claim() external override {
        require(!_shouldRevert, "MockFeeSource: claim reverted");
        if (_amount > 0) {
            _token.transfer(msg.sender, _amount);
        }
    }

    function setClaimableAmount(uint256 amount_) external {
        _amount = amount_;
    }

    function setShouldRevert(bool shouldRevert_) external {
        _shouldRevert = shouldRevert_;
    }
}
