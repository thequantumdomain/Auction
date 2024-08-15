// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract Auction {
    address public owner;
    IERC20 public token;
    uint256 public auctionEndTime;
    uint256 public totalTokens;
    bool public auctionEnded;
    uint256 public reservePrice;
    uint256 public startPrice;
    uint256 public priceDecreaseRate;
    uint256 public auctionDuration;
    uint256 public constant TIME_EXTENSION = 5 minutes;
    uint256 public constant BATCH_SIZE = 10;

    mapping(address => uint256) public bids;
    mapping(address => uint256) public maxBids;
    mapping(address => bool) public whitelist;
    address[] public bidderList;

    event AuctionStarted(
        uint256 duration,
        uint256 totalTokens,
        uint256 startPrice,
        uint256 reservePrice
    );
    event BidPlaced(address indexed bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);
    event Refund(address indexed bidder, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier auctionActive() {
        require(block.timestamp < auctionEndTime, "Auction has ended");
        require(!auctionEnded, "Auction already ended");
        _;
    }

    modifier auctionEndedOnly() {
        require(
            block.timestamp >= auctionEndTime || auctionEnded,
            "Auction still active"
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function startAuction(
        address _token,
        uint256 _duration,
        uint256 _totalTokens,
        uint256 _startPrice,
        uint256 _reservePrice,
        uint256 _priceDecreaseRate
    ) external onlyOwner {
        require(
            auctionEndTime == 0 || block.timestamp >= auctionEndTime,
            "Previous auction not ended"
        );
        token = IERC20(_token);
        require(
            token.balanceOf(address(this)) >= _totalTokens,
            "Not enough tokens for auction"
        );
        auctionEndTime = block.timestamp + _duration;
        totalTokens = _totalTokens;
        startPrice = _startPrice;
        reservePrice = _reservePrice;
        priceDecreaseRate = _priceDecreaseRate;
        auctionEnded = false;
        auctionDuration = _duration;
        emit AuctionStarted(
            _duration,
            _totalTokens,
            _startPrice,
            _reservePrice
        );
    }

    function addToWhitelist(address[] calldata _addresses) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = true;
        }
    }

    function removeFromWhitelist(
        address[] calldata _addresses
    ) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = false;
        }
    }

    function getCurrentPrice() public view returns (uint256) {
        if (block.timestamp >= auctionEndTime) return reservePrice;
        uint256 timeElapsed = block.timestamp -
            (auctionEndTime - auctionDuration);
        uint256 priceDrop = (timeElapsed * (startPrice - reservePrice)) /
            auctionDuration;
        return startPrice > priceDrop ? startPrice - priceDrop : reservePrice;
    }

    function placeBid() external payable auctionActive {
        require(whitelist[msg.sender], "Not whitelisted");
        require(msg.sender != owner, "Owner cannot place bids");
        require(msg.value > 0, "Bid must be greater than 0");
        require(msg.value >= getCurrentPrice(), "Bid too low");

        uint256 newBid = bids[msg.sender] + msg.value;
        require(newBid > maxBids[msg.sender], "Bid not higher than max bid");

        if (bids[msg.sender] == 0) {
            bidderList.push(msg.sender);
        }

        if (block.timestamp > auctionEndTime - TIME_EXTENSION) {
            auctionEndTime = block.timestamp + TIME_EXTENSION;
        }

        bids[msg.sender] = newBid;
        maxBids[msg.sender] = newBid;

        emit BidPlaced(msg.sender, msg.value);
    }

    function setMaxBid(uint256 _maxBid) external auctionActive {
        require(whitelist[msg.sender], "Not whitelisted");
        require(
            _maxBid > maxBids[msg.sender],
            "New max bid not higher than current max bid"
        );
        maxBids[msg.sender] = _maxBid;
    }

    function endAuction() external onlyOwner auctionEndedOnly {
        require(!auctionEnded, "Auction already ended");
        auctionEnded = true;

        uint256 totalBidAmount = 0;
        for (uint256 i = 0; i < bidderList.length; i++) {
            totalBidAmount += bids[bidderList[i]];
        }

        require(totalBidAmount >= reservePrice, "Reserve price not met");

        uint256 tokenDistributed = 0;
        for (uint256 i = 0; i < bidderList.length; i++) {
            address bidder = bidderList[i];
            uint256 tokenAmount = (bids[bidder] * totalTokens) / totalBidAmount;

            if (tokenAmount > 0) {
                require(
                    token.transfer(bidder, tokenAmount),
                    "Token transfer failed"
                );
                tokenDistributed += tokenAmount;
                emit AuctionEnded(bidder, tokenAmount);
            }
        }

        require(
            tokenDistributed <= totalTokens,
            "Distributed more tokens than available"
        );

        (bool success, ) = payable(owner).call{value: address(this).balance}(
            ""
        );
        require(success, "Failed to send Ether to owner");
    }

    function withdrawRemainingTokens() external onlyOwner auctionEndedOnly {
        uint256 remainingTokens = token.balanceOf(address(this));
        require(
            token.transfer(owner, remainingTokens),
            "Token transfer failed"
        );
    }

    function refund() external {
        require(auctionEnded, "Auction not ended");
        uint256 refundAmount = bids[msg.sender];
        require(refundAmount > 0, "No refund available");

        bids[msg.sender] = 0;
        maxBids[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund failed");

        emit Refund(msg.sender, refundAmount);
    }
}
