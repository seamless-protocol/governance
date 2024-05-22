// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {IStakingManager} from "src/interfaces/IStakingManager.sol";

contract User is Test {
    ERC20Mock public token;
    ERC20Mock public seam;
    IStakingManager public staking;

    constructor(ERC20Mock _token, ERC20Mock _seam, IStakingManager _staking) {
        token = _token;
        seam = _seam;
        staking = _staking;
    }

    function deposit(uint256 amount) external {
        token.approve(address(staking), amount);
        staking.stake(address(token), amount, address(this));
    }

    function depositSeam(uint256 amount) external {
        seam.approve(address(staking), amount);
        staking.stake(address(seam), amount, address(this));
    }

    function withdraw(uint256 amount) external {
        staking.unstake(address(token), amount, address(this));
    }

    function withdrawSeam(uint256 amount) external {
        staking.unstake(address(seam), amount, address(this));
    }

    function claimRewards() external {
        staking.claimRewards(address(token), address(this));
    }

    function claimRewardsSeam() external {
        staking.claimRewards(address(seam), address(this));
    }

    function transfer(address to, uint256 amount) external {
        IERC20(staking.getStakedToken(address(token))).transfer(to, amount);
    }
}
