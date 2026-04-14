// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PriceOracle
 * @notice 从Chainlink获取ETH和ERC20代币价格的合约
 */
contract PriceOracle is Ownable {
    
    // 从代币地址到价格预言机地址的映射
    mapping(address => AggregatorV3Interface) public priceFeeds;
    
    // 检查代币是否有价格预言机的映射
    mapping(address => bool) public hasPriceFeed;
    
    // ETH/USD价格预言机
    AggregatorV3Interface public ethUsdPriceFeed;
    
    // USD价格的小数位（Chainlink USD价格为8位小数）
    uint8 public constant USD_DECIMALS = 8;
    
    // ETH的小数位（18位小数）
    uint8 public constant ETH_DECIMALS = 18;
    
    event PriceFeedAdded(address indexed token, address indexed priceFeed);
    event PriceFeedRemoved(address indexed token);
    event EthUsdPriceFeedUpdated(address indexed priceFeed);
    
    constructor(address _ethUsdPriceFeed) Ownable(msg.sender) {
        require(_ethUsdPriceFeed != address(0), unicode"价格预言机：无效的ETH/USD价格预言机");
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        emit EthUsdPriceFeedUpdated(_ethUsdPriceFeed);
    }
    
    /**
     * @notice 为代币添加价格预言机
     * @param token 代币地址
     * @param priceFeed Chainlink价格预言机地址
     */
    function addPriceFeed(address token, address priceFeed) external onlyOwner {
        require(token != address(0), unicode"价格预言机：无效的代币地址");
        require(priceFeed != address(0), unicode"价格预言机：无效的价格预言机地址");
        
        priceFeeds[token] = AggregatorV3Interface(priceFeed);
        hasPriceFeed[token] = true;
        
        emit PriceFeedAdded(token, priceFeed);
    }
    
    /**
     * @notice 移除代币的价格预言机
     * @param token 代币地址
     */
    function removePriceFeed(address token) external onlyOwner {
        require(hasPriceFeed[token], unicode"价格预言机：代币没有价格预言机");
        
        delete priceFeeds[token];
        hasPriceFeed[token] = false;
        
        emit PriceFeedRemoved(token);
    }
    
    /**
     * @notice 更新ETH/USD价格预言机
     * @param _ethUsdPriceFeed 新的ETH/USD价格预言机地址
     */
    function setEthUsdPriceFeed(address _ethUsdPriceFeed) external onlyOwner {
        require(_ethUsdPriceFeed != address(0), unicode"价格预言机：无效的价格预言机");
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        emit EthUsdPriceFeedUpdated(_ethUsdPriceFeed);
    }
    
    /**
     * @notice 获取最新的ETH价格（USD）
     * @return price ETH价格（USD，8位小数）
     * @return timestamp 价格更新的时间戳
     */
    function getEthPrice() public view returns (uint256 price, uint256 timestamp) {
        (
            uint80 roundID,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethUsdPriceFeed.latestRoundData();
        
        require(answer > 0, unicode"价格预言机：无效的ETH价格");
        require(updatedAt > 0, unicode"价格预言机：轮次不完整");
        
        // 检查价格是否新鲜（1小时内）
        require(block.timestamp - updatedAt <= 3600, unicode"价格预言机：ETH价格过期");
        
        return (uint256(answer), updatedAt);
    }
    
    /**
     * @notice 获取最新的代币价格（USD）
     * @param token 代币地址
     * @return price 代币价格（USD，8位小数）
     * @return timestamp 价格更新的时间戳
     */
    function getTokenPrice(address token) public view returns (uint256 price, uint256 timestamp) {
        require(hasPriceFeed[token], unicode"价格预言机：代币没有价格预言机");
        
        (
            uint80 roundID,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeeds[token].latestRoundData();
        
        require(answer > 0, unicode"价格预言机：无效的代币价格");
        require(updatedAt > 0, unicode"价格预言机：轮次不完整");
        
        // 检查价格是否新鲜（1小时内）
        require(block.timestamp - updatedAt <= 3600, unicode"价格预言机：代币价格过期");
        
        return (uint256(answer), updatedAt);
    }
    
    /**
     * @notice 将ETH数量转换为USD价值
     * @param ethAmount ETH数量（18位小数）
     * @return usdValue USD价值（8位小数）
     */
    function ethToUsd(uint256 ethAmount) public view returns (uint256 usdValue) {
        (uint256 ethPrice, ) = getEthPrice();
        
        // ethAmount是18位小数，ethPrice是8位小数
        // 结果应该是8位小数
        usdValue = (ethAmount * ethPrice) / 10**ETH_DECIMALS;
        
        return usdValue;
    }
    
    /**
     * @notice 将代币数量转换为USD价值
     * @param token 代币地址
     * @param tokenAmount 代币数量
     * @param tokenDecimals 代币的小数位
     * @return usdValue USD价值（8位小数）
     */
    function tokenToUsd(address token, uint256 tokenAmount, uint8 tokenDecimals) 
        public 
        view 
        returns (uint256 usdValue) 
    {
        (uint256 tokenPrice, ) = getTokenPrice(token);
        
        // tokenAmount是tokenDecimals位小数，tokenPrice是8位小数
        // 结果应该是8位小数
        usdValue = (tokenAmount * tokenPrice) / 10**tokenDecimals;
        
        return usdValue;
    }
    
    /**
     * @notice 将USD价值转换为ETH数量
     * @param usdValue USD价值（8位小数）
     * @return ethAmount ETH数量（18位小数）
     */
    function usdToEth(uint256 usdValue) public view returns (uint256 ethAmount) {
        (uint256 ethPrice, ) = getEthPrice();
        
        // usdValue是8位小数，ethPrice是8位小数
        // 结果应该是18位小数
        ethAmount = (usdValue * 10**ETH_DECIMALS) / ethPrice;
        
        return ethAmount;
    }
    
    /**
     * @notice 将USD价值转换为代币数量
     * @param token 代币地址
     * @param usdValue USD价值（8位小数）
     * @param tokenDecimals 代币的小数位
     * @return tokenAmount 代币数量
     */
    function usdToToken(address token, uint256 usdValue, uint8 tokenDecimals) 
        public 
        view 
        returns (uint256 tokenAmount) 
    {
        (uint256 tokenPrice, ) = getTokenPrice(token);
        
        // usdValue是8位小数，tokenPrice是8位小数
        // 结果应该是tokenDecimals位小数
        tokenAmount = (usdValue * 10**tokenDecimals) / tokenPrice;
        
        return tokenAmount;
    }
    
    /**
     * @notice 比较两个投标的USD价值
     * @param bid1Amount 第一个投标金额
     * @param bid1Token 第一个投标代币地址（ETH为address(0)）
     * @param bid1Decimals 第一个投标代币的小数位
     * @param bid2Amount 第二个投标金额
     * @param bid2Token 第二个投标代币地址（ETH为address(0)）
     * @param bid2Decimals 第二个投标代币的小数位
     * @return comparison 1表示bid1>bid2，0表示相等，-1表示bid1<bid2
     */
    function compareBids(
        uint256 bid1Amount,
        address bid1Token,
        uint8 bid1Decimals,
        uint256 bid2Amount,
        address bid2Token,
        uint8 bid2Decimals
    ) external view returns (int8 comparison) {
        uint256 bid1Usd;
        uint256 bid2Usd;
        
        // Convert bid 1 to USD
        if (bid1Token == address(0)) {
            bid1Usd = ethToUsd(bid1Amount);
        } else {
            bid1Usd = tokenToUsd(bid1Token, bid1Amount, bid1Decimals);
        }
        
        // Convert bid 2 to USD
        if (bid2Token == address(0)) {
            bid2Usd = ethToUsd(bid2Amount);
        } else {
            bid2Usd = tokenToUsd(bid2Token, bid2Amount, bid2Decimals);
        }
        
        if (bid1Usd > bid2Usd) {
            return 1;
        } else if (bid1Usd < bid2Usd) {
            return -1;
        } else {
            return 0;
        }
    }
    
    /**
     * @notice 获取ETH/USD价格预言机的小数位数
     */
    function getEthPriceDecimals() external view returns (uint8) {
        return ethUsdPriceFeed.decimals();
    }
    
    /**
     * @notice 获取代币价格预言机的小数位数
     * @param token 代币地址
     */
    function getTokenPriceDecimals(address token) external view returns (uint8) {
        require(hasPriceFeed[token], unicode"价格预言机：代币没有价格预言机");
        return priceFeeds[token].decimals();
    }
}