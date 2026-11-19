// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NonceAgent} from "../src/NonceAgent.sol";
import {NonceMarket} from "../src/NonceMarket.sol";

contract MockAgentID2 {
    mapping(address => uint256) public balanceOf;

    function setHolder(address who, bool holds) external {
        balanceOf[who] = holds ? 1 : 0;
    }
}

interface Vm2 {
    function prank(address) external;
    function expectRevert(bytes4) external;
    function deal(address, uint256) external;
}

contract NonceMarketTest {
    Vm2 constant vm = Vm2(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockAgentID2 mock;
    NonceAgent nft;
    NonceMarket market;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant DIFF = 12;

    function setUp() public {
        mock = new MockAgentID2();
        nft = new NonceAgent(address(mock), 10, 2, DIFF, "https://example.com/meta/");
        market = new NonceMarket(address(nft));
        mock.setHolder(alice, true);
        vm.deal(bob, 10 ether);
        vm.deal(alice, 1 ether);
    }

    function assertEq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function assertTrue(bool c, string memory m) internal pure {
        require(c, m);
    }

    function solve(address who) internal view returns (uint256 nonce) {
        for (nonce = 0;; nonce++) {
            if (nft.isValidSolution(who, nonce)) return nonce;
        }
    }

    function mintAlice() internal returns (uint256 id) {
        uint256 nonce = solve(alice);
        vm.prank(alice);
        id = nft.mint(nonce);
    }

    function testListRequiresOwnership() public {
        uint256 id = mintAlice();
        vm.prank(bob);
        vm.expectRevert(NonceMarket.NotOwner.selector);
        market.list(id, 1 ether);
    }

    function testListRequiresApproval() public {
        uint256 id = mintAlice();
        vm.prank(alice);
        vm.expectRevert(NonceMarket.NotApproved.selector);
        market.list(id, 1 ether);
    }

    function testListAndBuy() public {
        uint256 id = mintAlice();
        vm.prank(alice);
        nft.approve(address(market), id);
        vm.prank(alice);
        market.list(id, 1 ether);
        assertEq(market.listedCount(), 1, "one listing");

        uint256 balBefore = alice.balance;
        vm.prank(bob);
        market.buy{value: 1 ether}(id);
        assertTrue(nft.ownerOf(id) == bob, "bob owns after buy");
        assertEq(alice.balance, balBefore + 1 ether, "seller paid in full");
        assertEq(market.listedCount(), 0, "listing removed");
    }

    function testBuyWrongPriceReverts() public {
        uint256 id = mintAlice();
        vm.prank(alice);
        nft.approve(address(market), id);
        vm.prank(alice);
        market.list(id, 1 ether);
        vm.prank(bob);
        vm.expectRevert(NonceMarket.WrongPayment.selector);
        market.buy{value: 0.5 ether}(id);
    }

    function testCancel() public {
        uint256 id = mintAlice();
        vm.prank(alice);
        nft.approve(address(market), id);
        vm.prank(alice);
        market.list(id, 1 ether);
        vm.prank(alice);
        market.cancel(id);
        assertEq(market.listedCount(), 0, "cancelled");
        (address seller,) = market.getListing(id);
        assertTrue(seller == address(0), "listing gone");
    }

    function testStaleAfterTransfer() public {
        uint256 id = mintAlice();
        vm.prank(alice);
        nft.setApprovalForAll(address(market), true);
        vm.prank(alice);
        market.list(id, 1 ether);
        // seller moves the NFT away -> listing goes stale
        vm.prank(alice);
        nft.transferFrom(alice, bob, id);
        vm.prank(bob);
        vm.expectRevert(NonceMarket.StaleListing.selector);
        market.buy{value: 1 ether}(id);
        market.cleanStale(id);
        assertEq(market.listedCount(), 0, "stale cleaned");
    }
}
