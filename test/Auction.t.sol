// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Auction.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
    address public bidder3;

    receive() external payable {}

    function setUp() public {
        owner = address(this);
        bidder1 = address(0x1);
        bidder2 = address(0x2);
        bidder3 = address(0x3);

        auction = new Auction();
        token = new MockERC20();

        token.transfer(address(auction), 100 * 10 ** 18);
        token.approve(address(auction), type(uint256).max);

        assertEq(
            token.balanceOf(address(auction)),
            100 * 10 ** 18,
            "Auction didn't receive tokens"
        );
        assertEq(
            token.allowance(address(this), address(auction)),
            type(uint256).max,
            "Approval failed"
        );
    }

    function testStartAuction() public {
        vm.prank(owner);
        auction.startAuction(
            address(token),
            1000,
            100 * 10 ** 18,
            5 ether,
            1 ether,
            0.001 ether
        );

        assertEq(
            auction.totalTokens(),
            100 * 10 ** 18,
            "Total tokens mismatch"
        );
        assertEq(
            address(auction.token()),
            address(token),
            "Token address mismatch"
        );
    }

    function testWhitelist() public {
        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = bidder1;
        toWhitelist[1] = bidder2;

        vm.prank(owner);
        auction.addToWhitelist(toWhitelist);

        assertTrue(auction.whitelist(bidder1), "Bidder1 not whitelisted");
        assertTrue(auction.whitelist(bidder2), "Bidder2 not whitelisted");
        assertFalse(auction.whitelist(bidder3), "Bidder3 whitelisted");
    }

    function testPlaceBid() public {
        vm.prank(owner);
        auction.startAuction(
            address(token),
            1000,
            100 * 10 ** 18,
            5 ether,
            1 ether,
            0.001 ether
        );

        address[] memory toWhitelist = new address[](1);
        toWhitelist[0] = bidder1;
        vm.prank(owner);
        auction.addToWhitelist(toWhitelist);

        vm.prank(bidder1);
        vm.deal(bidder1, 5 ether);
        auction.placeBid{value: 5 ether}();

        assertEq(auction.bids(bidder1), 5 ether, "Bid amount mismatch");
    }

    function testDutchAuction() public {
        vm.prank(owner);
        auction.startAuction(
            address(token),
            1000,
            100 * 10 ** 18,
            5 ether,
            1 ether,
            0.001 ether
        );

        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = bidder1;
        toWhitelist[1] = bidder2;
        vm.prank(owner);
        auction.addToWhitelist(toWhitelist);

        vm.warp(block.timestamp + 500);

        uint256 currentPrice = auction.getCurrentPrice();
        assertTrue(
            currentPrice < 5 ether && currentPrice > 1 ether,
            "Incorrect Dutch auction price"
        );

        vm.prank(bidder1);
        vm.deal(bidder1, currentPrice);
        auction.placeBid{value: currentPrice}();

        assertEq(auction.bids(bidder1), currentPrice, "Bid amount mismatch");
    }

    function testEndAuction() public {
        vm.prank(owner);
        auction.startAuction(
            address(token),
            1000,
            100 * 10 ** 18,
            5 ether,
            1 ether,
            0.001 ether
        );

        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = bidder1;
        toWhitelist[1] = bidder2;
        vm.prank(owner);
        auction.addToWhitelist(toWhitelist);

        uint256 currentPrice = auction.getCurrentPrice();

        vm.prank(bidder1);
        vm.deal(bidder1, currentPrice);
        auction.placeBid{value: currentPrice}();

        vm.prank(bidder2);
        vm.deal(bidder2, currentPrice);
        auction.placeBid{value: currentPrice}();

        vm.warp(block.timestamp + 1001);

        uint256 initialOwnerBalance = address(owner).balance;

        vm.prank(owner);
        auction.endAuction();

        uint256 bidder1TokenBalance = token.balanceOf(bidder1);
        uint256 bidder2TokenBalance = token.balanceOf(bidder2);
        uint256 finalOwnerBalance = address(owner).balance;

        assertEq(
            bidder1TokenBalance,
            50 * 10 ** 18,
            "Bidder1 token balance mismatch"
        );
        assertEq(
            bidder2TokenBalance,
            50 * 10 ** 18,
            "Bidder2 token balance mismatch"
        );
        assertEq(
            finalOwnerBalance,
            initialOwnerBalance + 2 * currentPrice,
            "Owner didn't receive correct ETH amount"
        );
    }

    function testRefund() public {
        vm.prank(owner);
        auction.startAuction(
            address(token),
            1000,
            100 * 10 ** 18,
            5 ether,
            1 ether,
            0.001 ether
        );

        address[] memory toWhitelist = new address[](2);
        toWhitelist[0] = bidder1;
        toWhitelist[1] = bidder2;
        vm.prank(owner);
        auction.addToWhitelist(toWhitelist);

        uint256 currentPrice = auction.getCurrentPrice();

        vm.prank(bidder1);
        vm.deal(bidder1, currentPrice);
        auction.placeBid{value: currentPrice}();

        // Bidder2 outbids Bidder1
        vm.prank(bidder2);
        vm.deal(bidder2, currentPrice + 1 ether);
        auction.placeBid{value: currentPrice + 1 ether}();

        vm.warp(block.timestamp + 1001);

        vm.prank(owner);
        auction.endAuction();

        uint256 initialBalance = bidder1.balance;

        vm.prank(bidder1);
        auction.refund();

        uint256 finalBalance = bidder1.balance;

        assertEq(
            finalBalance,
            initialBalance + currentPrice,
            "Refund amount mismatch"
        );
    }
}
