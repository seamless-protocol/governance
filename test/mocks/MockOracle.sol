// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";

contract MockOracle {
    constructor() {}

    function latestAnswer() external pure returns (uint256) {
        return 1;
    }
}
