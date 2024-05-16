// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IStaking} from "../interfaces/IStaking.sol";

contract StakedToken is ERC20, Ownable {
    address public stakingToken;
    IStaking public staking;

    constructor(
        address _staking,
        address _stakingToken,
        address _initialOwner,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {
        staking = IStaking(_staking);
        stakingToken = _stakingToken;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function _update(address sender, address recipient, uint256 amount) internal virtual override {
        staking.updateHook(stakingToken, sender, recipient, amount);
        return super._update(sender, recipient, amount);
    }
}
