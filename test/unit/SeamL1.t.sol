// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC165} from "openzeppelin-contracts/utils/introspection/IERC165.sol";
import {IOptimismMintableERC20} from "../../src/interfaces/IOptimismMintableERC20.sol";
import {SeamL1} from "../../src/SeamL1.sol";

contract SeamL1Test is Test {
    string constant NAME = "SEAM L1 Bridged";
    string constant SYMBOL = "SEAML1";

    address immutable bridge = makeAddr("BRIDGE");
    address immutable remoteToken = makeAddr("REMOTE_TOKEN");

    SeamL1 seamL1;

    function setUp() public {
        seamL1 = new SeamL1(bridge, remoteToken, NAME, SYMBOL);
    }

    function test_Deployed() public {
        assertEq(seamL1.bridge(), bridge);
        assertEq(seamL1.remoteToken(), remoteToken);
        assertEq(seamL1.decimals(), 18);
        assertEq(seamL1.name(), NAME);
        assertEq(seamL1.symbol(), SYMBOL);
        assertTrue(seamL1.supportsInterface(type(IOptimismMintableERC20).interfaceId));
        assertTrue(seamL1.supportsInterface(type(IERC165).interfaceId));
    }

    function testFuzz_MintBurn(uint256 amount) public {
        vm.startPrank(bridge);

        address alice = makeAddr("alice");

        seamL1.mint(alice, amount);
        assertEq(seamL1.balanceOf(alice), amount);

        seamL1.burn(alice, amount);
        assertEq(seamL1.balanceOf(alice), 0);

        vm.stopPrank();
    }

    function test_RevertIf_MintNotBridge() public {
        vm.expectRevert(SeamL1.NotBridge.selector);
        seamL1.mint(makeAddr("alice"), 1);
    }

    function test_RevertIf_BurnNotBridge() public {
        vm.expectRevert(SeamL1.NotBridge.selector);
        seamL1.burn(makeAddr("alice"), 1);
    }

    function testFuzz_Permit(uint256 amount) public {
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");

        deal(address(seamL1), alice, amount);

        bytes32 permitMessageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                seamL1.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        alice,
                        address(this),
                        amount,
                        seamL1.nonces(alice),
                        block.timestamp
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, permitMessageHash);

        seamL1.permit(alice, address(this), amount, block.timestamp, v, r, s);

        seamL1.transferFrom(alice, address(this), amount);

        assertEq(seamL1.balanceOf(address(this)), amount);
    }
}
