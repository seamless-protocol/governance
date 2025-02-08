// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEACAggregatorProxy} from "@aave/periphery-v3/contracts/misc/interfaces/IEACAggregatorProxy.sol";
import {StaticERC20Mock} from "./MockStaticToken.sol";

contract MockFactory {
    mapping(address => address) assetToStatic;

    constructor() {}

    /**
     * @notice Creates new staticATokens
     * @param underlyings the addresses of the underlyings to create.
     * @return address[] addresses of the new staticATokens.
     */
    function createStaticATokens(address[] memory underlyings, address[] memory aTokens)
        external
        returns (address[] memory)
    {
        for (uint8 i; i < underlyings.length; i++) {
            StaticERC20Mock token = new StaticERC20Mock(aTokens[i]);
            assetToStatic[underlyings[i]] = address(token);
        }
    }

    /**
     * @notice Returns all tokens deployed via this registry.
     * @return address[] list of tokens
     */
    function getStaticATokens() external view returns (address[] memory) {}

    /**
     * @notice Returns the staticAToken for a given underlying.
     * @param underlying the address of the underlying.
     * @return address the staticAToken address.
     */
    function getStaticAToken(address underlying) external view returns (address) {
        return assetToStatic[underlying];
    }
}
