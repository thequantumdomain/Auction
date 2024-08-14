// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Auction Contract
 * @notice This contract allows the owner to start an auction with ERC20 tokens,
 *         users to place bids, and the owner to end the auction and distribute tokens to the highest bidders.
 */
contract Auction {
    // State variables
    address public owner;
    IERC20 public token;
    uint256 public auctionEndTime;
    uint256 public totalTokens;
    bool public auctionEnded;

    // Mapping of bidders to their bid amounts
    mapping(address => uint256) public bids;

    // Events
    event AuctionStarted(uint256 duration, uint256 totalTokens);
    event BidPlaced(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 amount);

    // Modifiers
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
        owner = msg.sender; // Set contract deployer as owner
    }

    /**
     * @notice Starts the auction with a specified duration and quantity of ERC20 tokens.
     * @dev Only the owner can start the auction.
     * @param _token Address of the ERC20 token to be auctioned.
     * @param _duration Duration of the auction in seconds.
     * @param _totalTokens Number of tokens to be auctioned.
     */
    function startAuction(
        address _token,
        uint256 _duration,
        uint256 _totalTokens
    ) external onlyOwner {
        require(
            auctionEndTime == 0 || block.timestamp >= auctionEndTime,
            "Previous auction not ended"
        );
        token = IERC20(_token);
        auctionEndTime = block.timestamp + _duration;
        totalTokens = _totalTokens;
        auctionEnded = false;
        emit AuctionStarted(_duration, _totalTokens);
    }

    /**
     * @notice Allows users to place bids on the auctioned tokens.
     * @dev Only non-owner users can place bids. Auction must be active.
     */
    function placeBid() external payable auctionActive {
        require(msg.sender != owner, "Owner cannot place bids");
        require(msg.value > 0, "Bid must be greater than 0");

        bids[msg.sender] += msg.value;
        emit BidPlaced(msg.sender, msg.value);
    }

    /**
     * @notice Ends the auction and distributes tokens to the highest bidders proportionally.
     * @dev Only the owner can end the auction. Auction must have ended.
     */
    function endAuction() external onlyOwner auctionEndedOnly {
        require(!auctionEnded, "Auction already ended");

        auctionEnded = true;
        uint256 totalBidAmount = address(this).balance;

        for (uint256 i = 0; i < totalTokens; i++) {
            address highestBidder = findHighestBidder();
            uint256 tokenAmount = (bids[highestBidder] * totalTokens) /
                totalBidAmount;

            // Transfer the corresponding token amount to the highest bidder
            token.transfer(highestBidder, tokenAmount);
            bids[highestBidder] = 0; // Clear the bid amount
            emit AuctionEnded(highestBidder, tokenAmount);
        }

        // Transfer remaining ETH to the owner
        payable(owner).transfer(address(this).balance);
    }

    /**
     * @notice Finds the highest bidder for the auction.
     * @return highestBidder Address of the highest bidder.
     */
    function findHighestBidder() internal view returns (address highestBidder) {
        uint256 highestBid = 0;
        for (uint256 i = 0; i < totalTokens; i++) {
            if (bids[highestBidder] > highestBid) {
                highestBid = bids[highestBidder];
                highestBidder = highestBidder;
            }
        }
    }
}
