// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockRewardsController {
    event ActionHandled(address indexed user, uint256 totalSupply, uint256 oldUserBalance);
    mapping(address => address) internal _transferStrategies;
    constructor() {}

    function handleAction(address user, uint256 totalSupply, uint256 oldUserBalance) external {
        emit ActionHandled(user, totalSupply, oldUserBalance);
    }

    function getTransferStrategy(address reward) external view returns (address) {
        return _transferStrategies[reward];
    }

    function _addTransferStrategy(address reward, address strat) external {
        _transferStrategies[reward] = strat;
    }
}