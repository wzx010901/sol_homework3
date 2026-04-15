// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./PriceOracle.sol";
import "hardhat/console.sol";


/**
 * @title NFTAuction
 * @notice 去中心化NFT拍卖市场，集成Chainlink价格预言机
 * @dev 使用UUPS代理模式实现可升级性
 */
contract NFTAuction is Initializable, ReentrancyGuard, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    
    struct Auction {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 startPrice;
        uint256 reservePrice;
        uint256 minBidIncrement;
        uint256 startTime;
        uint256 endTime;
        address highestBidder;
        uint256 highestBidAmount;
        address highestBidToken;
        uint8 highestBidDecimals;
        bool ended;
        bool claimed;
        uint256 createdAt;
    }
    
    struct Bid {
        address bidder;
        uint256 amount;
        address token;
        uint8 decimals;
        uint256 timestamp;
        uint256 usdValue;
    }
    
    uint256 public auctionCounter;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Bid[]) public auctionBids;
    mapping(uint256 => mapping(address => uint256)) public pendingReturns;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public pendingTokenReturns;
    
    PriceOracle public priceOracle;
    uint256 public platformFeePercent;
    uint256 public constant MAX_PLATFORM_FEE = 1000;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_AUCTION_DURATION = 5 minutes;
    uint256 public constant MAX_AUCTION_DURATION = 30 days;
    uint256 public constant DEFAULT_MIN_BID_INCREMENT = 500;
    
    address public feeRecipient;
    mapping(address => bool) public supportedBidTokens;
    
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 startTime,
        uint256 endTime
    );
    
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount,
        address token,
        uint256 usdValue
    );
    
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid,
        address winningToken
    );
    
    event AuctionClaimed(
        uint256 indexed auctionId,
        address indexed winner,
        address indexed seller,
        uint256 sellerProceeds,
        uint256 platformFee
    );
    
    event WithdrawalMade(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );
    
    event TokenWithdrawalMade(
        uint256 indexed auctionId,
        address indexed bidder,
        address indexed token,
        uint256 amount
    );
    
    event SupportedTokenAdded(address indexed token);
    event SupportedTokenRemoved(address indexed token);
    event PlatformFeeUpdated(uint256 newFeePercent);
    event FeeRecipientUpdated(address newRecipient);
    event PriceOracleUpdated(address newOracle);
    event AuctionExtended(uint256 indexed auctionId, uint256 newEndTime);
    
      /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    }


    modifier auctionExists(uint256 auctionId) {
        require(auctions[auctionId].seller != address(0), unicode"拍卖：拍卖不存在");
        _;
    }
    
    modifier auctionActive(uint256 auctionId) {
        require(block.timestamp >= auctions[auctionId].startTime, unicode"拍卖：拍卖未开始");
        require(block.timestamp <= auctions[auctionId].endTime, unicode"拍卖：拍卖已结束");
        require(!auctions[auctionId].ended, unicode"拍卖：拍卖已经结束");
        _;
    }
    
    modifier auctionEnded(uint256 auctionId) {
        require(block.timestamp > auctions[auctionId].endTime || auctions[auctionId].ended, 
                unicode"拍卖：拍卖未结束");
        _;
    }
    
    function initialize(
        address _priceOracle,
        address _feeRecipient,
        uint256 _platformFeePercent
    ) public initializer {
        __Pausable_init();
        __Ownable_init(_feeRecipient);
        
        require(_priceOracle != address(0), unicode"拍卖：无效的价格预言机");
        require(_feeRecipient != address(0), unicode"拍卖：无效的费用接收者");
        require(_platformFeePercent <= MAX_PLATFORM_FEE, unicode"拍卖：费用过高");
        priceOracle = PriceOracle(_priceOracle);
        feeRecipient = _feeRecipient;
        platformFeePercent = _platformFeePercent;
        auctionCounter = 0;
    }
    
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 reservePrice,
        uint256 minBidIncrement,
        uint256 duration
    ) external whenNotPaused returns (uint256) {
        require(nftContract != address(0), unicode"拍卖：无效的NFT合约");
        require(duration >= MIN_AUCTION_DURATION, unicode"拍卖：持续时间太短");
        require(duration <= MAX_AUCTION_DURATION, unicode"拍卖：持续时间太长");
        require(startPrice > 0, unicode"拍卖：起拍价必须大于0");
        require(reservePrice >= startPrice, unicode"拍卖：保留价低于起拍价");
        
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, unicode"拍卖：不是代币所有者");
        require(
            nft.getApproved(tokenId) == address(this) || 
            nft.isApprovedForAll(msg.sender, address(this)),
            unicode"拍卖：合约未获批准"
        );
        
        nft.transferFrom(msg.sender, address(this), tokenId);
        
        uint256 auctionId = ++auctionCounter;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        
        auctions[auctionId] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            startPrice: startPrice,
            reservePrice: reservePrice,
            minBidIncrement: minBidIncrement > 0 ? minBidIncrement : DEFAULT_MIN_BID_INCREMENT,
            startTime: startTime,
            endTime: endTime,
            highestBidder: address(0),
            highestBidAmount: 0,
            highestBidToken: address(0),
            highestBidDecimals: 0,
            ended: false,
            claimed: false,
            createdAt: block.timestamp
        });
        
        emit AuctionCreated(
            auctionId,
            msg.sender,
            nftContract,
            tokenId,
            startPrice,
            reservePrice,
            startTime,
            endTime
        );
        
        return auctionId;
    }
    
    function placeBidETH(uint256 auctionId) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
        auctionExists(auctionId) 
        auctionActive(auctionId) 
    {
        require(msg.value > 0, "Bid: must send ETH");
        
        Auction storage auction = auctions[auctionId];
        uint256 bidUsdValue = priceOracle.ethToUsd(msg.value);
        _validateBid(auction, msg.value, address(0), 18, bidUsdValue);
        
        if (auction.highestBidder != address(0)) {
            pendingReturns[auctionId][auction.highestBidder] += auction.highestBidAmount;
        }
        
        auction.highestBidder = msg.sender;
        auction.highestBidAmount = msg.value;
        auction.highestBidToken = address(0);
        auction.highestBidDecimals = 18;
        
        auctionBids[auctionId].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            token: address(0),
            decimals: 18,
            timestamp: block.timestamp,
            usdValue: bidUsdValue
        }));
        
        if (auction.endTime - block.timestamp < 5 minutes) {
            auction.endTime += 5 minutes;
            emit AuctionExtended(auctionId, auction.endTime);
        }
        
        emit BidPlaced(auctionId, msg.sender, msg.value, address(0), bidUsdValue);
    }
    
    function placeBidToken(uint256 auctionId, address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        auctionExists(auctionId)
        auctionActive(auctionId)
    {
        require(token != address(0), unicode"投标：无效的代币");
        require(supportedBidTokens[token], unicode"投标：代币不支持");
        require(amount > 0, unicode"投标：金额必须大于0");
        
        Auction storage auction = auctions[auctionId];
        uint8 decimals = IERC20Metadata(token).decimals();
        uint256 bidUsdValue = priceOracle.tokenToUsd(token, amount, decimals);
        _validateBid(auction, amount, token, decimals, bidUsdValue);
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        if (auction.highestBidder != address(0)) {
            if (auction.highestBidToken == address(0)) {
                pendingReturns[auctionId][auction.highestBidder] += auction.highestBidAmount;
            } else {
                pendingTokenReturns[auctionId][auction.highestBidToken][auction.highestBidder] += auction.highestBidAmount;
            }
        }
        
        auction.highestBidder = msg.sender;
        auction.highestBidAmount = amount;
        auction.highestBidToken = token;
        auction.highestBidDecimals = decimals;
        
        auctionBids[auctionId].push(Bid({
            bidder: msg.sender,
            amount: amount,
            token: token,
            decimals: decimals,
            timestamp: block.timestamp,
            usdValue: bidUsdValue
        }));
        
        if (auction.endTime - block.timestamp < 5 minutes) {
            auction.endTime += 5 minutes;
            emit AuctionExtended(auctionId, auction.endTime);
        }
        
        emit BidPlaced(auctionId, msg.sender, amount, token, bidUsdValue);
    }
    
    //结束拍卖
    function endAuction(uint256 auctionId)
        external
        nonReentrant
        auctionExists(auctionId)
        auctionEnded(auctionId)
    {
        Auction storage auction = auctions[auctionId];
        require(!auction.ended, unicode"拍卖：已经结束");
        require(!auction.claimed, unicode"拍卖：已经领取");
        
        auction.ended = true;
        
        if (auction.highestBidder != address(0)) {
            uint256 highestBidUsd = _getBidUsdValue(
                auction.highestBidAmount,
                auction.highestBidToken,
                auction.highestBidDecimals
            );
            
            if (highestBidUsd >= auction.reservePrice) {
                IERC721(auction.nftContract).transferFrom(
                    address(this),
                    auction.highestBidder,
                    auction.tokenId
                );
                
                emit AuctionEnded(
                    auctionId,
                    auction.highestBidder,
                    auction.highestBidAmount,
                    auction.highestBidToken
                );
            } else {
                // 将最高出价者的资金添加到待返还列表
                if (auction.highestBidToken == address(0)) {
                    pendingReturns[auctionId][auction.highestBidder] += auction.highestBidAmount;
                } else {
                    pendingTokenReturns[auctionId][auction.highestBidToken][auction.highestBidder] += auction.highestBidAmount;
                }
            }
        }
        
        if (auction.highestBidder == address(0)) {
            IERC721(auction.nftContract).transferFrom(
                address(this),
                auction.seller,
                auction.tokenId
            );
        }
    }
    
    /**- 当卖家调用该函数时，会检查最高出价是否达到保留价
    - 如果未达到保留价，函数会直接结束，不会进行任何资金分配
    - 最高出价者的资金会保留在 pendingReturns 或 pendingTokenReturns 中
    **/
    function claimProceeds(uint256 auctionId)
        external
        nonReentrant
        auctionExists(auctionId)
    {
        Auction storage auction = auctions[auctionId];
        require(auction.ended, unicode"拍卖：未结束");
        require(!auction.claimed, unicode"拍卖：已经领取");
        require(msg.sender == auction.seller, unicode"拍卖：不是卖家");
        
        auction.claimed = true;
        
        if (auction.highestBidder != address(0)) {
            uint256 highestBidUsd = _getBidUsdValue(
                auction.highestBidAmount,
                auction.highestBidToken,
                auction.highestBidDecimals
            );
            
            if (highestBidUsd >= auction.reservePrice) {
                uint256 platformFee = (auction.highestBidAmount * platformFeePercent) / BASIS_POINTS;
                uint256 sellerProceeds = auction.highestBidAmount - platformFee;
                
                if (auction.highestBidToken == address(0)) {
                    (bool feeSuccess, ) = payable(feeRecipient).call{value: platformFee}("");
                    require(feeSuccess, unicode"拍卖：费用转账失败");
                    
                    (bool sellerSuccess, ) = payable(auction.seller).call{value: sellerProceeds}("");
                    require(sellerSuccess, unicode"拍卖：卖家转账失败");
                } else {
                    IERC20(auction.highestBidToken).safeTransfer(feeRecipient, platformFee);
                    IERC20(auction.highestBidToken).safeTransfer(auction.seller, sellerProceeds);
                }
                
                emit AuctionClaimed(
                    auctionId,
                    auction.highestBidder,
                    auction.seller,
                    sellerProceeds,
                    platformFee
                );
            }
        }
    }
    
    /**- 当用户调用该函数时，会检查是否有待提现的资金
    - 有资金时，函数会将资金转账给用户
    - 无资金时，函数会直接返回
    **/
    function withdraw(uint256 auctionId) external nonReentrant auctionExists(auctionId) {
        uint256 amount = pendingReturns[auctionId][msg.sender];
        require(amount > 0, unicode"提现：无资金");
        
        pendingReturns[auctionId][msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, unicode"提现：转账失败");
        
        emit WithdrawalMade(auctionId, msg.sender, amount);
    }
    
    /**
     * 
     */
    function withdrawToken(uint256 auctionId, address token) 
        external 
        nonReentrant 
        auctionExists(auctionId) 
    {
        uint256 amount = pendingTokenReturns[auctionId][token][msg.sender];
        require(amount > 0, unicode"提现：无代币");
        
        pendingTokenReturns[auctionId][token][msg.sender] = 0;
        
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit TokenWithdrawalMade(auctionId, msg.sender, token, amount);
        Auction storage auction = auctions[auctionId];
        //判断当前是否最高出价
        if (auction.highestBidder != address(0)) {
            uint256 highestBidUsd = _getBidUsdValue(
                auction.highestBidAmount,
                auction.highestBidToken,
                auction.highestBidDecimals
            );
            if (auction.highestBidder == msg.sender) {
                if (highestBidUsd >= auction.reservePrice) {
           
            // 添加：当出价未达保留价时，将NFT返回给卖家
                    IERC721(auction.nftContract).transferFrom(
                        address(this),
                        auction.seller,
                        auction.tokenId
                    );
                }
            }
        }
    }
    
    function cancelAuction(uint256 auctionId) 
        external 
        nonReentrant 
        auctionExists(auctionId) 
        auctionActive(auctionId) 
    {
        Auction storage auction = auctions[auctionId];
        require(msg.sender == auction.seller, unicode"拍卖：不是卖家");
        require(auction.highestBidder == address(0), unicode"拍卖：存在投标");
        
        auction.ended = true;
        auction.claimed = true;
        
        IERC721(auction.nftContract).transferFrom(
            address(this),
            auction.seller,
            auction.tokenId
        );
    }
    
    function addSupportedBidToken(address token) external onlyOwner {
        require(token != address(0), unicode"管理员：无效的代币");
        supportedBidTokens[token] = true;
        emit SupportedTokenAdded(token);
    }
    
    function removeSupportedBidToken(address token) external onlyOwner {
        supportedBidTokens[token] = false;
        emit SupportedTokenRemoved(token);
    }
    
    function setPlatformFeePercent(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= MAX_PLATFORM_FEE, unicode"管理员：费用过高");
        platformFeePercent = newFeePercent;
        emit PlatformFeeUpdated(newFeePercent);
    }
    
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), unicode"管理员：无效的接收者");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }
    
    function setPriceOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), unicode"管理员：无效的预言机");
        priceOracle = PriceOracle(newOracle);
        emit PriceOracleUpdated(newOracle);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        return auctions[auctionId];
    }
    
    function getBids(uint256 auctionId) external view returns (Bid[] memory) {
        return auctionBids[auctionId];
    }
    
    function getBidCount(uint256 auctionId) external view returns (uint256) {
        return auctionBids[auctionId].length;
    }
    
    function getHighestBidUsdValue(uint256 auctionId) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        if (auction.highestBidder == address(0)) {
            return 0;
        }
        return _getBidUsdValue(
            auction.highestBidAmount,
            auction.highestBidToken,
            auction.highestBidDecimals
        );
    }
    
    function hasEnded(uint256 auctionId) external view returns (bool) {
        return block.timestamp > auctions[auctionId].endTime || auctions[auctionId].ended;
    }
    
    function getMinNextBidUsd(uint256 auctionId) external view returns (uint256) {
        Auction storage auction = auctions[auctionId];
        
        if (auction.highestBidder == address(0)) {
            return auction.startPrice;
        }
        
        uint256 highestBidUsd = _getBidUsdValue(
            auction.highestBidAmount,
            auction.highestBidToken,
            auction.highestBidDecimals
        );
        
        return highestBidUsd + (highestBidUsd * auction.minBidIncrement) / BASIS_POINTS;
    }
    
    function getMinNextBidEth(uint256 auctionId) external view returns (uint256) {
        uint256 minBidUsd = this.getMinNextBidUsd(auctionId);
        return priceOracle.usdToEth(minBidUsd);
    }
    
    function getMinNextBidToken(uint256 auctionId, address token, uint8 decimals) 
        external 
        view 
        returns (uint256) 
    {
        uint256 minBidUsd = this.getMinNextBidUsd(auctionId);
        return priceOracle.usdToToken(token, minBidUsd, decimals);
    }
    
    function _validateBid(
        Auction storage auction,
        uint256 amount,
        address token,
        uint8 decimals,
        uint256 bidUsdValue
    ) internal view {
        if (auction.highestBidder == address(0)) {
            require(bidUsdValue >= auction.startPrice, unicode"投标：低于起拍价");
        } else {
            uint256 highestBidUsd = _getBidUsdValue(
                auction.highestBidAmount,
                auction.highestBidToken,
                auction.highestBidDecimals
            );
            
            uint256 minBidUsd = highestBidUsd + (highestBidUsd * auction.minBidIncrement) / BASIS_POINTS;
            require(bidUsdValue >= minBidUsd, unicode"投标：低于最小加价幅度");
        }
    }
    
    function _getBidUsdValue(
        uint256 amount,
        address token,
        uint8 decimals
    ) internal view returns (uint256) {
        if (token == address(0)) {
            return priceOracle.ethToUsd(amount);
        } else {
            return priceOracle.tokenToUsd(token, amount, decimals);
        }
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    receive() external payable {}
}
