// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {IStakedToken} from "src/interfaces/IStakedToken.sol";

contract User is Test {
    ERC20Mock public token;
    IStakedToken public stakedToken;

    constructor(ERC20Mock _token, IStakedToken _stakedToken) {
        token = _token;
        stakedToken = _stakedToken;
    }

    function deposit(uint256 amount) external {
        token.approve(address(stakedToken), amount);
        stakedToken.deposit(amount, address(this));
    }

    function withdraw(uint256 amount) external {
        stakedToken.withdraw(amount, address(this));
    }

    function claimRewards() external {
        stakedToken.claimRewards(address(this));
    }

    function transfer(address to, uint256 amount) external {
        stakedToken.transfer(to, amount);
    }
}
