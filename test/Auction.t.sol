// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Auction.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MKT") {
        _mint(msg.sender, 1000 * 10 ** 18);
    }
}

contract AuctionTest is Test {
    Auction public auction;
    MockERC20 public token;
    address public owner;
    address public bidder1;
    address public bidder2;

    function setUp() public {
        owner = address(this); // Test contract is the owner
        bidder1 = address(0x1);
        bidder2 = address(0x2);

        auction = new Auction();
        token = new MockERC20();
    }

    function testStartAuction() public {
        vm.prank(owner);
        auction.startAuction(address(token), 1000, 100 * 10 ** 18);

        assertEq(auction.totalTokens(), 100 * 10 ** 18);
        assertEq(auction.token(), address(token));
    }

    function testPlaceBid() public {
        vm.prank(owner);
        auction.startAuction(address(token), 1000, 100 * 10 ** 18);

        vm.prank(bidder1);
        auction.placeBid{value: 1 ether}();

        assertEq(auction.bids(bidder1), 1 ether);
    }

    function testEndAuction() public {
        vm.prank(owner);
        auction.startAuction(address(token), 1000, 100 * 10 ** 18);

        vm.prank(bidder1);
        auction.placeBid{value: 2 ether}();

        vm.prank(bidder2);
        auction.placeBid{value: 3 ether}();

        // Fast forward time to after the auction ends
        vm.warp(block.timestamp + 1001);

        vm.prank(owner);
        auction.endAuction();

        assertEq(token.balanceOf(bidder1), 40 * 10 ** 18);
        assertEq(token.balanceOf(bidder2), 60 * 10 ** 18);
    }
}
