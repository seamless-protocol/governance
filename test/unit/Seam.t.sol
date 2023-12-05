// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Seam, Initializable} from "src/Seam.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

contract SeamTest is Test {
    Seam public tokenImplementation;
    Seam public tokenProxy;

    address _alice;
    uint256 _alicePk;

    function setUp() public {
        (_alice, _alicePk) = makeAddrAndKey("alice");

        tokenImplementation = new Seam();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(tokenImplementation),
            abi.encodeWithSelector(
                Seam.initialize.selector,
                "test token name",
                "test token symbol",
                100
            )
        );
        tokenProxy = Seam(address(proxy));
    }

    function testDeployed() public {
        assertEq(tokenProxy.name(), "test token name");
        assertEq(tokenProxy.symbol(), "test token symbol");
        assertEq(tokenProxy.decimals(), 18);
        assertEq(tokenProxy.totalSupply(), 100);
        assertEq(tokenProxy.hasRole(tokenProxy.DEFAULT_ADMIN_ROLE(), address(this)), true);
        assertEq(tokenProxy.hasRole(tokenProxy.UPGRADER_ROLE(), address(this)), true);
        assertEq(tokenProxy.clock(), block.timestamp);
        assertEq(tokenProxy.CLOCK_MODE(), "mode=timestamp");
    }

    function testTransfer() public {
        tokenProxy.delegate(_alice);
        tokenProxy.transfer(_alice, 100);

        assertEq(tokenProxy.getVotes(address(this)), 0);
        assertEq(tokenProxy.balanceOf(_alice), 100);
    }

    function testDelegate() public {
        tokenProxy.delegate(address(this));
        assertEq(tokenProxy.getVotes(address(this)), tokenProxy.totalSupply());
    }

    function testPermit() public {
        tokenProxy.transfer(_alice, 100);

        bytes32 permitMessageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                tokenProxy.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        _alice,
                        address(this),
                        10,
                        tokenProxy.nonces(_alice),
                        block.timestamp
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_alicePk, permitMessageHash);

        tokenProxy.permit(_alice, address(this), 10, block.timestamp, v, r, s);

        tokenProxy.transferFrom(_alice, address(this), 10);

        assertEq(tokenProxy.balanceOf(address(this)), 10);
    }

    function testUpgrade() public {
        address newImplementation = address(new Seam());

        tokenProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        // Revert on upgrade when not owner
        vm.startPrank(_alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, _alice, tokenProxy.UPGRADER_ROLE()
            )
        );
        tokenProxy.upgradeToAndCall(address(newImplementation), abi.encodePacked());

        vm.stopPrank();

        // Revert when already initialized
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        tokenProxy.upgradeToAndCall(
            address(newImplementation),
            abi.encodeWithSelector(Seam.initialize.selector, "test token name", "test token symbol", 100)
        );
    }
}
