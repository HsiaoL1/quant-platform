// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract PriceOracle is Ownable {
    mapping(string => address) public priceFeeds;
    mapping(string => uint8) public feedDecimals;
    
    uint256 public constant STALENESS_THRESHOLD = 3 hours;
    uint256 public constant PRICE_PRECISION = 10**18;
    
    event PriceFeedAdded(string indexed pair, address indexed priceFeed);
    event PriceFeedRemoved(string indexed pair);
    event PriceUpdate(string indexed pair, int256 price, uint256 timestamp);
    
    constructor() Ownable(msg.sender) {}
    
    function addPriceFeed(string memory pair, address priceFeed) external onlyOwner {
        require(priceFeed != address(0), "Price feed cannot be zero address");
        require(bytes(pair).length > 0, "Pair cannot be empty");
        
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        uint8 decimals = feed.decimals();
        
        priceFeeds[pair] = priceFeed;
        feedDecimals[pair] = decimals;
        
        emit PriceFeedAdded(pair, priceFeed);
    }
    
    function removePriceFeed(string memory pair) external onlyOwner {
        require(priceFeeds[pair] != address(0), "Price feed does not exist");
        
        delete priceFeeds[pair];
        delete feedDecimals[pair];
        
        emit PriceFeedRemoved(pair);
    }
    
    function getLatestPrice(string memory pair) external view returns (int256, uint256) {
        address priceFeed = priceFeeds[pair];
        require(priceFeed != address(0), "Price feed not found");
        
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        
        require(price > 0, "Invalid price from oracle");
        require(updatedAt > 0, "Round not complete");
        require(block.timestamp - updatedAt <= STALENESS_THRESHOLD, "Price data is stale");
        
        return (price, updatedAt);
    }
    
    function getLatestPriceWithDecimals(string memory pair) external view returns (int256, uint8, uint256) {
        (int256 price, uint256 updatedAt) = this.getLatestPrice(pair);
        uint8 decimals = feedDecimals[pair];
        
        return (price, decimals, updatedAt);
    }
    
    function getNormalizedPrice(string memory pair) external view returns (uint256) {
        (int256 price, uint256 updatedAt) = this.getLatestPrice(pair);
        uint8 decimals = feedDecimals[pair];
        
        require(price > 0, "Price must be positive");
        
        uint256 normalizedPrice;
        if (decimals < 18) {
            normalizedPrice = uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            normalizedPrice = uint256(price) / (10 ** (decimals - 18));
        } else {
            normalizedPrice = uint256(price);
        }
        
        return normalizedPrice;
    }
    
    function isPriceFeedActive(string memory pair) external view returns (bool) {
        address priceFeed = priceFeeds[pair];
        if (priceFeed == address(0)) {
            return false;
        }
        
        try this.getLatestPrice(pair) returns (int256, uint256) {
            return true;
        } catch {
            return false;
        }
    }
    
    function getSupportedPairs() external view returns (string[] memory) {
        // Note: This is a simplified implementation
        // In production, you might want to maintain a list of active pairs
        string[] memory pairs = new string[](0);
        return pairs;
    }
}