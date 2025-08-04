// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PriceOracle} from "../src/PriceOracle.sol";

// Mock Chainlink Aggregator for testing
contract MockAggregatorV3 {
    uint8 public decimals;
    string public description;
    uint256 public version;
    
    int256 private _price;
    uint256 private _updatedAt;
    uint80 private _roundId;
    
    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
        version = 1;
        _roundId = 1;
    }
    
    function setPrice(int256 price) external {
        _price = price;
        _updatedAt = block.timestamp;
        _roundId++;
    }
    
    function setStalePrice(int256 price, uint256 staleness) external {
        _price = price;
        if (staleness >= block.timestamp) {
            _updatedAt = 0;
        } else {
            _updatedAt = block.timestamp - staleness;
        }
        _roundId++;
    }
    
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
    
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
}

contract PriceOracleTest is Test {
    PriceOracle public oracle;
    MockAggregatorV3 public ethUsdFeed;
    MockAggregatorV3 public btcUsdFeed;
    
    address public owner;
    address public user1 = address(0x1);
    
    string constant ETH_USD = "ETH/USD";
    string constant BTC_USD = "BTC/USD";
    
    function setUp() public {
        owner = address(this);
        oracle = new PriceOracle();
        
        // Create mock price feeds
        ethUsdFeed = new MockAggregatorV3(8, "ETH/USD");
        btcUsdFeed = new MockAggregatorV3(8, "BTC/USD");
        
        // Set initial prices
        ethUsdFeed.setPrice(2000e8); // $2000 with 8 decimals
        btcUsdFeed.setPrice(50000e8); // $50000 with 8 decimals
    }
    
    function testOwnership() public {
        assertEq(oracle.owner(), owner);
    }
    
    function testAddPriceFeed() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        
        assertEq(oracle.priceFeeds(ETH_USD), address(ethUsdFeed));
        assertEq(oracle.feedDecimals(ETH_USD), 8);
    }
    
    function testAddPriceFeedOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
    }
    
    function testAddPriceFeedZeroAddress() public {
        vm.expectRevert("Price feed cannot be zero address");
        oracle.addPriceFeed(ETH_USD, address(0));
    }
    
    function testAddPriceFeedEmptyPair() public {
        vm.expectRevert("Pair cannot be empty");
        oracle.addPriceFeed("", address(ethUsdFeed));
    }
    
    function testRemovePriceFeed() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        oracle.removePriceFeed(ETH_USD);
        
        assertEq(oracle.priceFeeds(ETH_USD), address(0));
        assertEq(oracle.feedDecimals(ETH_USD), 0);
    }
    
    function testRemoveNonExistentPriceFeed() public {
        vm.expectRevert("Price feed does not exist");
        oracle.removePriceFeed(ETH_USD);
    }
    
    function testGetLatestPrice() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        
        (int256 price, uint256 updatedAt) = oracle.getLatestPrice(ETH_USD);
        
        assertEq(price, 2000e8);
        assertEq(updatedAt, block.timestamp);
    }
    
    function testGetLatestPriceNonExistentFeed() public {
        vm.expectRevert("Price feed not found");
        oracle.getLatestPrice(ETH_USD);
    }
    
    function testGetLatestPriceStaleData() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        
        // Advance time to make current timestamp larger than 4 hours
        vm.warp(block.timestamp + 5 hours);
        
        // Set stale price (4 hours old from current time)
        ethUsdFeed.setStalePrice(2000e8, 4 hours);
        
        vm.expectRevert("Price data is stale");
        oracle.getLatestPrice(ETH_USD);
    }
    
    function testGetLatestPriceWithDecimals() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        
        (int256 price, uint8 decimals, uint256 updatedAt) = oracle.getLatestPriceWithDecimals(ETH_USD);
        
        assertEq(price, 2000e8);
        assertEq(decimals, 8);
        assertEq(updatedAt, block.timestamp);
    }
    
    function testGetNormalizedPrice() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        
        uint256 normalizedPrice = oracle.getNormalizedPrice(ETH_USD);
        
        // $2000 with 8 decimals should be normalized to 18 decimals
        // 2000e8 * 10^(18-8) = 2000e18
        assertEq(normalizedPrice, 2000e18);
    }
    
    function testGetNormalizedPriceHigherDecimals() public {
        // Create a mock feed with 18 decimals
        MockAggregatorV3 feed18 = new MockAggregatorV3(18, "TEST/USD");
        feed18.setPrice(2000e18);
        
        oracle.addPriceFeed("TEST/USD", address(feed18));
        
        uint256 normalizedPrice = oracle.getNormalizedPrice("TEST/USD");
        
        // 18 decimals should remain unchanged
        assertEq(normalizedPrice, 2000e18);
    }
    
    function testIsPriceFeedActive() public {
        // Non-existent feed should be inactive
        assertFalse(oracle.isPriceFeedActive(ETH_USD));
        
        // Add and test active feed
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        assertTrue(oracle.isPriceFeedActive(ETH_USD));
        
        // Make feed stale and test inactive
        vm.warp(block.timestamp + 5 hours);
        ethUsdFeed.setStalePrice(2000e8, 4 hours);
        assertFalse(oracle.isPriceFeedActive(ETH_USD));
    }
    
    function testMultiplePriceFeeds() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        oracle.addPriceFeed(BTC_USD, address(btcUsdFeed));
        
        (int256 ethPrice,) = oracle.getLatestPrice(ETH_USD);
        (int256 btcPrice,) = oracle.getLatestPrice(BTC_USD);
        
        assertEq(ethPrice, 2000e8);
        assertEq(btcPrice, 50000e8);
    }
    
    function testPriceUpdateEvent() public {
        oracle.addPriceFeed(ETH_USD, address(ethUsdFeed));
        
        // The price update would be logged when the external oracle updates
        // For this test, we just verify the feed was added correctly
        assertEq(oracle.priceFeeds(ETH_USD), address(ethUsdFeed));
    }
}