// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Seam
 * @author Seamless Protocol
 * @notice An ERC-20 token that is upgradeable.
 */
contract Seam is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the token and inherited contracts.
     * @param name Token name
     * @param symbol Token symbol
     */
    function initialize(string calldata name, string calldata symbol, uint256 intialSupply) external initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        _mint(msg.sender, intialSupply);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
