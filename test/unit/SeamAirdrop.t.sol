// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ISeamAirdrop} from "src/interfaces/ISeamAirdrop.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {SeamAirdrop} from "src/SeamAirdrop.sol";

contract SeamAirdropTest is Test {
    address immutable token = address(new ERC20Mock());

    /// This merkle root is generater from the following JSON
    /// {
    ///    "0x016C8780e5ccB32E5CAA342a926794cE64d9C364": 10,
    ///    "0x185a4dc360ce69bdccee33b3784b0282f7961aea": 100
    /// }
    bytes32 immutable merkleRoot = 0xd0aa6a4e5b4e13462921d7518eebdb7b297a7877d6cfe078b0c318827392fb55;
    SeamAirdrop seamAirdrop;

    bytes32 immutable user1Proof = 0x005a0033b5a1ac5c2872d7689e0f064ad6d2287ab98439e44c822e1c46530033;
    bytes32 immutable user2Proof = 0xceeae64152a2deaf8c661fccd5645458ba20261b16d2f6e090fe908b0ac9ca88;
    address immutable user1 = 0x016C8780e5ccB32E5CAA342a926794cE64d9C364;
    address immutable user2 = 0x185a4dc360CE69bDCceE33b3784B0282f7961aea;

    function setUp() public {
        seamAirdrop = new SeamAirdrop(IERC20(token), merkleRoot, address(this));
    }

    function test_SetUp() public {
        assertEq(address(seamAirdrop.seam()), token);
        assertEq(seamAirdrop.merkleRoot(), merkleRoot);
        assertEq(seamAirdrop.owner(), address(this));
    }

    function testFuzz_SetMerkleRoot(bytes32 newMerkleRoot) public {
        seamAirdrop.setMerkleRoot(newMerkleRoot);
        assertEq(seamAirdrop.merkleRoot(), newMerkleRoot);
    }

    function testFuzz_SetMerkleRoot_RevertIf_NotOwner(address caller, bytes32 newMerkleRoot) public {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        seamAirdrop.setMerkleRoot(newMerkleRoot);
        vm.stopPrank();
    }

    function test_Claim() public {
        uint256 initialBalance = type(uint256).max;
        deal(token, address(seamAirdrop), initialBalance);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = user1Proof;
        seamAirdrop.claim(user1, 10 ether, proof);

        assertEq(IERC20(token).balanceOf(user1), 10 ether);
        assertTrue(seamAirdrop.hasClaimed(user1));
        assertEq(IERC20(token).balanceOf(address(seamAirdrop)), initialBalance - 10 ether);

        proof[0] = user2Proof;
        seamAirdrop.claim(user2, 100 ether, proof);

        assertEq(IERC20(token).balanceOf(user2), 100 ether);
        assertTrue(seamAirdrop.hasClaimed(user2));
        assertEq(IERC20(token).balanceOf(address(seamAirdrop)), initialBalance - 10 ether - 100 ether);
    }

    function test_Claim_RevertIf_AlreadyClaimed() public {
        uint256 initialBalance = type(uint256).max;
        deal(token, address(seamAirdrop), initialBalance);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = user1Proof;
        seamAirdrop.claim(user1, 10 ether, proof);

        vm.expectRevert(abi.encodeWithSelector(ISeamAirdrop.AlreadyClaimed.selector, user1));
        seamAirdrop.claim(user1, 10 ether, proof);
    }

    function testFuzz_Claim_RevertIf_InvalidProof(bytes32 userProof) public {
        vm.assume(userProof != user1Proof);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = userProof;

        vm.expectRevert(ISeamAirdrop.InvalidProof.selector);
        seamAirdrop.claim(user1, 10 ether, proof);
    }
}