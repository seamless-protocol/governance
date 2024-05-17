// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {IStaking} from "src/interfaces/IStaking.sol";

contract User is Test {
    ERC20Mock public token;
    IStaking public staking;

    constructor(ERC20Mock _token, IStaking _staking) {
        token = _token;
        staking = _staking;
    }

    function deposit(uint256 amount) external {
        token.approve(address(staking), amount);
        staking.stake(address(token), amount, address(this));
    }

    function withdraw(uint256 amount) external {
        staking.unstake(address(token), amount, address(this));
    }

    function claimRewards() external {
        staking.claimRewards(address(token), address(this));
    }

    function transfer(address to, uint256 amount) external {
        IERC20(staking.getStakedToken(address(token))).transfer(to, amount);
    }
}
