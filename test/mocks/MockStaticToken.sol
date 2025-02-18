// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract StaticERC20Mock is ERC20 {
    address aToken;

    constructor(address _aToken) ERC20("ERC20Mock", "E20M") {
        aToken = _aToken;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function deposit(uint256 amount, address to, uint16 code, bool depositToAave) external returns (uint256) {
        _mint(to, amount);
        ERC20(aToken).transferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function redeem(uint256 amount, address to, address referral, bool isWithdraw)
        external
        returns (uint256, uint256)
    {
        _burn(msg.sender, amount);
        ERC20(aToken).transfer(to, amount);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return assets;
    }
}
