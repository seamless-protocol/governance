// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";

contract MockPool {
    address[] internal _reserves;
    mapping(address => DataTypes.ReserveData) internal _reservesData;
    address internal _treasury;

    constructor(address[] memory reserves, address treasury) {
        _reserves = reserves;
        _treasury = treasury;
    }

    function getReservesList() external view returns (address[] memory) {
        return _reserves;
    }

    // For this test, we assume `mintToTreasury` just no-ops or updates an internal state
    function mintToTreasury(address[] calldata rewards) external {
        // no-op for testing
        for (uint256 i; i < rewards.length; i++) {
            ERC20Mock token = ERC20Mock(_reservesData[rewards[i]].aTokenAddress);
            token.mint(_treasury, 1000 ether);
        }
    }

    // We’ll simulate some aToken addresses here
    function setReserveData(address underlyingAsset, address aTokenAddress) external returns (address) {
        DataTypes.ReserveData storage data = _reservesData[underlyingAsset];
        ERC20Mock aToken = new ERC20Mock();
        data.aTokenAddress = address(aToken);
        return address(aToken);
    }

    function setTreasury(address treasure) external {
        _treasury = treasure;
    }

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return _reservesData[asset];
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        ERC20Mock token = ERC20Mock(_reservesData[asset].aTokenAddress);
        token.burn(to, 1000 ether);
        ERC20Mock assetToken = ERC20Mock(asset);
        assetToken.mint(to, 1000 ether);
        // no-op, pretend we transferred tokens
        return amount;
    }
}
