// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IStakingManager} from "../interfaces/IStakingManager.sol";
import {StakedTokenStorage as Storage} from "../storage/StakedTokenStorage.sol";

contract StakedToken is ERC20Upgradeable, OwnableUpgradeable {
    function initialize(address _staking, address _stakingToken, string memory _name, string memory _symbol)
        external
        initializer
    {
        __ERC20_init(_name, _symbol);
        __Ownable_init(_staking);

        Storage.Layout storage $ = Storage.layout();
        $.staking = _staking;
        $.stakingToken = _stakingToken;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function _update(address sender, address recipient, uint256 amount) internal virtual override {
        Storage.Layout storage $ = Storage.layout();
        IStakingManager($.staking).updateHook($.stakingToken, sender, recipient, amount);

        return super._update(sender, recipient, amount);
    }

    receive() external payable {}
}
