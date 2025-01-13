// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

contract MockPool  {
    address[] internal _reserves;
    mapping(address => DataTypes.ReserveData) internal _reservesData;
    address internal _treasury;

    constructor(address[] memory reserves, address treasury) {
        _reserves = reserves;
        _treasury = treasury;
    }

    // minimal stubs needed for RewardKeeper calls

    function getReservesList() external view returns (address[] memory) {
        return _reserves;
    }

    // For this test, we assume `mintToTreasury` just no-ops or updates an internal state
    function mintToTreasury(address[] calldata) external {
        // no-op for testing
    }

    // We’ll simulate some aToken addresses here
    function setReserveData(address underlyingAsset, address aTokenAddress) external {
        DataTypes.ReserveData storage data = _reservesData[underlyingAsset];
        data.aTokenAddress = aTokenAddress;
    }

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return _reservesData[asset];
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        // no-op, pretend we transferred tokens
        return amount;
    }
}