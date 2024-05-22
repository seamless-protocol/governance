// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {Proxy} from "openzeppelin-contracts/proxy/Proxy.sol";
import {IStakingManager} from "../interfaces/IStakingManager.sol";

contract StakedTokenBeaconProxy is Proxy {
    address private immutable _beacon;

    constructor(address beacon, bytes memory data) {
        _beacon = beacon;

        if (data.length > 0) {
            Address.functionDelegateCall(_implementation(), data);
        }
    }

    function _implementation() internal view virtual override returns (address) {
        return IStakingManager(_getBeacon()).getStakedTokenImplementation();
    }

    function _getBeacon() internal view virtual returns (address) {
        return _beacon;
    }
}
