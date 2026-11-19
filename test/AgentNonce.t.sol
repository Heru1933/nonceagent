// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentNonce} from "../src/AgentNonce.sol";

contract MockAgentID {
    mapping(address => uint256) public balanceOf;

    function setHolder(address who, bool holds) external {
        balanceOf[who] = holds ? 1 : 0;
    }
}

interface Vm {
    function prank(address) external;
    function expectRevert(bytes4) external;
}

contract AgentNonceTest {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockAgentID mock;
    AgentNonce nft;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant DIFF = 12; // ~4k hashes per solution — fast in tests

    function setUp() public {
        mock = new MockAgentID();
        nft = new AgentNonce(address(mock), 10, 2, DIFF, "https://example.com/meta/");
        mock.setHolder(alice, true);
    }

    function assertEq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function assertTrue(bool c, string memory m) internal pure {
        require(c, m);
    }

    function solve(address who) internal view returns (uint256 nonce) {
        for (nonce = 0; ; nonce++) {
            if (nft.isValidSolution(who, nonce)) return nonce;
        }
    }

    function testNonAgentCannotMint() public {
        uint256 nonce = solve(bob);
        vm.prank(bob);
        vm.expectRevert(AgentNonce.NotAgent.selector);
        nft.mint(nonce);
    }

    function testBadNonceReverts() public {
        uint256 bad = 0;
        while (nft.isValidSolution(alice, bad)) bad++;
        vm.prank(alice);
        vm.expectRevert(AgentNonce.InvalidNonce.selector);
        nft.mint(bad);
    }

    function testMintWithValidNonce() public {
        uint256 nonce = solve(alice);
        vm.prank(alice);
        uint256 id = nft.mint(nonce);
        assertEq(id, 1, "first token id 1");
        assertTrue(nft.ownerOf(1) == alice, "alice owns 1");
        assertEq(nft.balanceOf(alice), 1, "balance 1");
        assertEq(nft.mintedBy(alice), 1, "mintedBy 1");
    }

    function testSameNonceCannotBeReplayed() public {
        uint256 nonce = solve(alice);
        vm.prank(alice);
        nft.mint(nonce);
        // mintIndex changed, so the old solution must now be invalid
        assertTrue(!nft.isValidSolution(alice, nonce), "old nonce invalid after mint");
    }

    function testSolutionIsWalletBound() public {
        mock.setHolder(bob, true);
        uint256 alicesNonce = solve(alice);
        assertTrue(!nft.isValidSolution(bob, alicesNonce), "alice's nonce useless for bob");
    }

    function testWalletCap() public {
        uint256 n1 = solve(alice);
        vm.prank(alice);
        nft.mint(n1);
        uint256 n2 = solve(alice);
        vm.prank(alice);
        nft.mint(n2);
        uint256 n3 = solve(alice);
        vm.prank(alice);
        vm.expectRevert(AgentNonce.WalletCapReached.selector);
        nft.mint(n3);
    }

    function testTransferWorks() public {
        uint256 nonce = solve(alice);
        vm.prank(alice);
        nft.mint(nonce);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);
        assertTrue(nft.ownerOf(1) == bob, "bob owns after transfer");
    }
}
