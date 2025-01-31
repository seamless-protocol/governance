// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {AToken} from "@aave/core-v3/contracts/protocol/tokenization/AToken.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';

contract MockPool {
    address[] internal _reserves;
    mapping(address => DataTypes.ReserveData) internal _reservesData;
    address internal _treasury;
    IPoolAddressesProvider public ADDRESSES_PROVIDER;
    uint256 index = 1000000000000000000000000000;

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
            AToken token = AToken(_reservesData[rewards[i]].aTokenAddress);
            token.mint(_treasury, _treasury, 1000 ether, index);
        }
    }

    // We’ll simulate some aToken addresses here
    function setReserveData(address underlyingAsset, address aTokenAddress) external returns (address) {
        DataTypes.ReserveData storage data = _reservesData[underlyingAsset];
        AToken aToken = new AToken(IPool(address(this)));
        data.aTokenAddress = address(aToken);
        return address(aToken);
    }

    function finalizeTransfer(
    address asset,
    address from,
    address to,
    uint256 amount,
    uint256 balanceFromBefore,
    uint256 balanceToBefore
  ) external virtual {
    // index++;
  }

    function setTreasury(address treasure) external {
        _treasury = treasure;
    }

    function getReserveData(address asset) external view returns (DataTypes.ReserveData memory) {
        return _reservesData[asset];
    }

    function getReserveNormalizedIncome(address reserve) external returns (uint256) {
        return index;
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
