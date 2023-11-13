// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IAirdrop} from "src/interfaces/IAirdrop.sol";
import {IEscrowSeam} from "src/interfaces/IEscrowSeam.sol";
import {ERC20Mock} from "openzeppelin-contracts/mocks/token/ERC20Mock.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {EscrowSeamAirdrop} from "src/airdrop/EscrowSeamAirdrop.sol";

contract EscrowSeamAirdropTest is Test {
    address immutable token = address(new ERC20Mock());

    /// This merkle root is generated from the following JSON
    /// {
    ///    "0x016C8780e5ccB32E5CAA342a926794cE64d9C364": 10,
    ///    "0x185a4dc360ce69bdccee33b3784b0282f7961aea": 100
    /// }
    bytes32 immutable merkleRoot =
        0xd0aa6a4e5b4e13462921d7518eebdb7b297a7877d6cfe078b0c318827392fb55;
    EscrowSeamAirdrop escrowSeamAirdrop;

    address immutable escrowSeam = makeAddr("escrowSeam");
    address immutable user1 = 0x016C8780e5ccB32E5CAA342a926794cE64d9C364;
    address immutable user2 = 0x185a4dc360CE69bDCceE33b3784B0282f7961aea;
    bytes32 immutable user1Proof =
        0x005a0033b5a1ac5c2872d7689e0f064ad6d2287ab98439e44c822e1c46530033;
    bytes32 immutable user2Proof =
        0xceeae64152a2deaf8c661fccd5645458ba20261b16d2f6e090fe908b0ac9ca88;

    function setUp() public {
        escrowSeamAirdrop = new EscrowSeamAirdrop(
            IERC20(token),
            IEscrowSeam(escrowSeam),
            merkleRoot,
            address(this)
        );
    }

    function test_SetUp() public {
        assertEq(address(escrowSeamAirdrop.seam()), token);
        assertEq(address(escrowSeamAirdrop.escrowSeam()), escrowSeam);
        assertEq(escrowSeamAirdrop.merkleRoot(), merkleRoot);
        assertEq(escrowSeamAirdrop.owner(), address(this));
    }

    function testFuzz_SetMerkleRoot(bytes32 newMerkleRoot) public {
        escrowSeamAirdrop.setMerkleRoot(newMerkleRoot);
        assertEq(escrowSeamAirdrop.merkleRoot(), newMerkleRoot);
    }

    function testFuzz_SetMerkleRoot_RevertIf_NotOwner(
        address caller,
        bytes32 newMerkleRoot
    ) public {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                caller
            )
        );
        escrowSeamAirdrop.setMerkleRoot(newMerkleRoot);
        vm.stopPrank();
    }

    function testFuzz_Withdraw(address recipient, uint256 amount) public {
        deal(token, address(escrowSeamAirdrop), amount);
        escrowSeamAirdrop.withdraw(recipient, amount);
        assertEq(IERC20(token).balanceOf(recipient), amount);
        assertEq(IERC20(token).balanceOf(address(escrowSeamAirdrop)), 0);
    }

    function testFuzz_Withdraw_RevertIf_NotOwner(
        address caller,
        address recipient,
        uint256 amount
    ) public {
        vm.assume(caller != address(this));
        vm.startPrank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                caller
            )
        );
        escrowSeamAirdrop.withdraw(recipient, amount);
        vm.stopPrank();
    }

    function test_Claim() public {
        uint256 initialBalance = type(uint256).max;
        deal(token, address(escrowSeamAirdrop), initialBalance);

        uint256 user1Claim = 10 ether;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = user1Proof;

        vm.startPrank(user1);
        vm.mockCall(
            escrowSeam,
            abi.encodeWithSelector(
                IEscrowSeam.deposit.selector,
                user1,
                user1Claim
            ),
            abi.encodePacked()
        );
        vm.expectCall(
            escrowSeam,
            abi.encodeWithSelector(
                IEscrowSeam.deposit.selector,
                user1,
                user1Claim
            )
        );
        escrowSeamAirdrop.claim(user1, user1Claim, proof);
        vm.stopPrank();

        assertTrue(escrowSeamAirdrop.hasClaimed(user1));
        assertEq(IERC20(token).balanceOf(escrowSeam), 0);
    }

    function test_Claim_RevertIf_AlreadyClaimed() public {
        uint256 initialBalance = type(uint256).max;
        deal(token, address(escrowSeamAirdrop), initialBalance);

        uint256 user1Claim = 10 ether;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = user1Proof;
        vm.mockCall(
            escrowSeam,
            abi.encodeWithSelector(
                IEscrowSeam.deposit.selector,
                user1,
                user1Claim
            ),
            abi.encodePacked()
        );
        vm.startPrank(user1);
        escrowSeamAirdrop.claim(user1, user1Claim, proof);

        vm.expectRevert(
            abi.encodeWithSelector(IAirdrop.AlreadyClaimed.selector, user1)
        );
        escrowSeamAirdrop.claim(user1, user1Claim, proof);

        vm.stopPrank();
    }

    function testFuzz_Claim_RevertIf_InvalidProof(
        address caller,
        uint256 amount,
        bytes32 userProof
    ) public {
        vm.assume(userProof != user1Proof);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = userProof;

        vm.startPrank(caller);
        vm.expectRevert(IAirdrop.InvalidProof.selector);
        escrowSeamAirdrop.claim(user1, amount, proof);
        vm.stopPrank();
    }

    function testFuzz_Claim_RevertIf_InvalidAmount(uint256 amount) public {
        vm.assume(amount != 10 ether);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = user1Proof;

        vm.startPrank(user1);
        vm.expectRevert(IAirdrop.InvalidProof.selector);
        escrowSeamAirdrop.claim(user1, amount, proof);
        vm.stopPrank();
    }
}
