import { expect } from "chai";
import { network } from "hardhat";
import { getAddress, parseEther } from "viem";
import { describe, it } from "node:test";

describe("NFTAuction 合约", async function () {
  const { viem } = await network.connect();
  const ETH_PRICE = 200000000000n;
  const TOKEN_PRICE = 100000000n;

  async function deployAuctionFixture() {
    const [owner, seller, bidder1, bidder2, feeRecipient] = await viem.getWalletClients();
    const publicClient = await viem.getPublicClient();

    const ethUsdPriceFeed = await viem.deployContract("MockV3Aggregator", [8, ETH_PRICE]);
    const tokenUsdPriceFeed = await viem.deployContract("MockV3Aggregator", [8, TOKEN_PRICE]);

    const priceOracle = await viem.deployContract("PriceOracle", [ethUsdPriceFeed.address]);

    const bidToken = await viem.deployContract("MockERC20", [
      "Bid Token",
      "BID",
      6,
      parseEther("1000000"),
    ]);

    await priceOracle.write.addPriceFeed([bidToken.address, tokenUsdPriceFeed.address]);

    const nft = await viem.deployContract("NFT", [
      "Auction NFT",
      "ANFT",
      "https://api.example.com/metadata/",
    ]);

    const auction = await viem.deployContract("NFTAuction");

    await auction.write.initialize([priceOracle.address, feeRecipient.account.address, 250n]);
    await feeRecipient.writeContract({
      address: auction.address,
      abi: auction.abi,
      functionName: "addSupportedBidToken",
      args: [bidToken.address]
    });

    await nft.write.mint([seller.account.address, "token-uri-1"]);
    await nft.write.mint([seller.account.address, "token-uri-2"]);

    return {
      viem,
      auction,
      nft,
      priceOracle,
      bidToken,
      ethUsdPriceFeed,
      tokenUsdPriceFeed,
      owner,
      seller,
      bidder1,
      bidder2,
      feeRecipient,
      publicClient,
    };
  }

  describe("初始化", function () {
    it("使用正确的参数初始化", async function () {
      const { auction, priceOracle, feeRecipient } = await deployAuctionFixture();

      expect(await auction.read.priceOracle()).to.equal(getAddress(priceOracle.address));
      expect(await auction.read.feeRecipient()).to.equal(getAddress(feeRecipient.account.address));
      expect(await auction.read.platformFeePercent()).to.equal(250n);
      expect(await auction.read.auctionCounter()).to.equal(0n);
    });

    it("设置正确的所有者", async function () {
      const { auction, feeRecipient } = await deployAuctionFixture();

      expect(await auction.read.owner()).to.equal(getAddress(feeRecipient.account.address));
    });
  });

  describe("创建拍卖", function () {
    it("创建新的拍卖", async function () {
      const { auction, nft, seller, publicClient } = await deployAuctionFixture();

      const sellerNft = await viem.getContractAt("NFT", nft.address);
      await seller.writeContract({
        address: nft.address,
        abi: sellerNft.abi,
        functionName: "approve",
        args: [auction.address, 0n]
      });

      const sellerAuction = await viem.getContractAt("NFTAuction", auction.address);

      const startPrice = 1000000000n;
      const reservePrice = 5000000000n;
      const duration = 86400n;

      const tx = await seller.writeContract({
        address: auction.address,
        abi: sellerAuction.abi,
        functionName: "createAuction",
        args: [nft.address, 0n, startPrice, reservePrice, 500n, duration]
      });

      await publicClient.waitForTransactionReceipt({ hash: tx });

      const auctionData = await auction.read.getAuction([1n]);
      expect(auctionData.seller).to.equal(getAddress(seller.account.address));
      expect(auctionData.nftContract).to.equal(getAddress(nft.address));
      expect(auctionData.tokenId).to.equal(0n);
      expect(auctionData.startPrice).to.equal(startPrice);
      expect(auctionData.reservePrice).to.equal(reservePrice);
    });

    it("将NFT转移到拍卖合约", async function () {
      const { auction, nft, seller } = await deployAuctionFixture();

      const sellerNft = await viem.getContractAt("NFT", nft.address);
      await seller.writeContract({
        address: nft.address,
        abi: sellerNft.abi,
        functionName: "approve",
        args: [auction.address, 0n]
      });

      const sellerAuction = await viem.getContractAt("NFTAuction", auction.address);

      await seller.writeContract({
        address: auction.address,
        abi: sellerAuction.abi,
        functionName: "createAuction",
        args: [nft.address, 0n, 1000000000n, 5000000000n, 500n, 86400n]
      });

      expect(await nft.read.ownerOf([0n])).to.equal(getAddress(auction.address));
    });
  });

  describe("使用ETH出价", function () {
    async function createAuctionFixture() {
      const base = await deployAuctionFixture();
      const { auction, nft, seller } = base;

      const sellerNft = await viem.getContractAt("NFT", nft.address);
      await seller.writeContract({
        address: nft.address,
        abi: sellerNft.abi,
        functionName: "approve",
        args: [auction.address, 0n]
      });

      const sellerAuction = await viem.getContractAt("NFTAuction", auction.address);

      await seller.writeContract({
        address: auction.address,
        abi: sellerAuction.abi,
        functionName: "createAuction",
        args: [nft.address, 0n, 1000000000n, 5000000000n, 500n, 86400n]
      });

      return { ...base, auctionId: 1n };
    }

    it("进行ETH出价", async function () {
      const { auction, bidder1, auctionId } = await createAuctionFixture();

      const bidAmount = parseEther("0.1");

      await bidder1.writeContract({
        address: auction.address,
        abi: auction.abi,
        functionName: "placeBidETH",
        args: [auctionId],
        value: bidAmount
      });

      const auctionData = await auction.read.getAuction([auctionId]);
      expect(auctionData.highestBidder).to.equal(getAddress(bidder1.account.address));
      expect(auctionData.highestBidAmount).to.equal(bidAmount);
    });

    it("不允许低于起拍价的出价", async function (t) {
      const { auction, bidder1, auctionId } = await createAuctionFixture();

      const bidder1Auction = await viem.getContractAt("NFTAuction", auction.address);

      const bidAmount = parseEther("0.001");

      try {
        await bidder1Auction.write.placeBidETH([auctionId], {
          value: bidAmount,
          walletClient: bidder1,
        });
        t.fail("交易被拒绝");
      } catch (error: any) {
        expect(error.message).to.include("投标：低于起拍价");
      }
    });

    it("要求最低加价幅度", async function (t) {
      const { auction, bidder1, bidder2, auctionId } = await createAuctionFixture();

      await bidder1.writeContract({
        address: auction.address,
        abi: auction.abi,
        functionName: "placeBidETH",
        args: [auctionId],
        value: parseEther("0.1")
      });

      try {
        await bidder2.writeContract({
          address: auction.address,
          abi: auction.abi,
          functionName: "placeBidETH",
          args: [auctionId],
          value: parseEther("0.101")
        });
        t.fail("交易被拒绝");
      } catch (error: any) {
        expect(error.message).to.include("投标：低于最小加价幅度");
      }

      await bidder2.writeContract({
        address: auction.address,
        abi: auction.abi,
        functionName: "placeBidETH",
        args: [auctionId],
        value: parseEther("0.11")
      });

      const auctionData = await auction.read.getAuction([auctionId]);
      expect(auctionData.highestBidder).to.equal(getAddress(bidder2.account.address));
    });

    it("退款", async function () {
      const { auction, bidder1, bidder2, auctionId } = await createAuctionFixture();

      await bidder1.writeContract({
        address: auction.address,
        abi: auction.abi,
        functionName: "placeBidETH",
        args: [auctionId],
        value: parseEther("0.1")
      });

      await bidder2.writeContract({
        address: auction.address,
        abi: auction.abi,
        functionName: "placeBidETH",
        args: [auctionId],
        value: parseEther("0.15")
      });

      const pendingReturn = await auction.read.pendingReturns([auctionId, bidder1.account.address]);
      expect(pendingReturn).to.equal(parseEther("0.1"));
    });
  });

  describe("使用 ERC20 代币进行出价", function () {
    async function createAuctionFixture() {
      const base = await deployAuctionFixture();
      const { auction, nft, seller, bidToken, bidder1 } = base;

      const sellerNft = await viem.getContractAt("NFT", nft.address);
      await seller.writeContract({
        address: nft.address,
        abi: sellerNft.abi,
        functionName: "approve",
        args: [auction.address, 0n]
      });

      const sellerAuction = await viem.getContractAt("NFTAuction", auction.address);

      await seller.writeContract({
        address: auction.address,
        abi: sellerAuction.abi,
        functionName: "createAuction",
        args: [nft.address, 0n, 1000000000n, 5000000000n, 500n, 86400n]
      });

      await bidToken.write.transfer([bidder1.account.address, 100000n * 10n ** 6n]);

      return { ...base, auctionId: 1n };
    }

    it("发起出价", async function () {
      const { auction, bidToken, bidder1, auctionId } = await createAuctionFixture();

      const bidder1Token = await viem.getContractAt("MockERC20", bidToken.address);

      await bidder1.writeContract({
        address: bidToken.address,
        abi: bidder1Token.abi,
        functionName: "approve",
        args: [auction.address, 100n * 10n ** 6n]
      });

      await bidder1.writeContract({
        address: auction.address,
        abi: auction.abi,
        functionName: "placeBidToken",
        args: [auctionId, bidToken.address, 100n * 10n ** 6n]
      });

      const auctionData = await auction.read.getAuction([auctionId]);
      expect(auctionData.highestBidder).to.equal(getAddress(bidder1.account.address));
      expect(auctionData.highestBidAmount).to.equal(100n * 10n ** 6n);
      expect(auctionData.highestBidToken).to.equal(getAddress(bidToken.address));
    });

    it("不允许不支持的代币", async function (t) {
      const { auction, bidder1, auctionId } = await createAuctionFixture();

      const bidder1Auction = await viem.getContractAt("NFTAuction", auction.address);

      const unsupportedToken = await viem.deployContract("MockERC20", [
        "Unsupported",
        "UNS",
        6,
        parseEther("1000000"),
      ]);

      try {
        await bidder1Auction.write.placeBidToken([auctionId, unsupportedToken.address, 100n * 10n ** 6n], { walletClient: bidder1 });
        t.fail("交易被拒绝");
      } catch (error: any) {
        expect(error.message).to.include("投标：代币不支持");
      }
    });
  });

  describe("管理员功能", function () {
    it("更新平台费用", async function () {
      const { auction, feeRecipient } = await deployAuctionFixture();

      const feeRecipientAuction = await viem.getContractAt("NFTAuction", auction.address);

      await feeRecipient.writeContract({
        address: auction.address,
        abi: feeRecipientAuction.abi,
        functionName: "setPlatformFeePercent",
        args: [500n]
      });

      expect(await auction.read.platformFeePercent()).to.equal(500n);
    });

    it("不允许费用高于最大值", async function (t) {
      const { auction, feeRecipient } = await deployAuctionFixture();

      const feeRecipientAuction = await viem.getContractAt("NFTAuction", auction.address);

      try {
        await feeRecipient.writeContract({
          address: auction.address,
          abi: feeRecipientAuction.abi,
          functionName: "setPlatformFeePercent",
          args: [1500n]
        });
        t.fail("交易被拒绝");
      } catch (error: any) {
        expect(error.message).to.include("管理员：费用过高");
      }
    });

    it("暂停和取消合约", async function () {
      const { auction, feeRecipient } = await deployAuctionFixture();

      const feeRecipientAuction = await viem.getContractAt("NFTAuction", auction.address);

      await feeRecipient.writeContract({
        address: auction.address,
        abi: feeRecipientAuction.abi,
        functionName: "pause"
      });
      expect(await auction.read.paused()).to.equal(true);

      await feeRecipient.writeContract({
        address: auction.address,
        abi: feeRecipientAuction.abi,
        functionName: "unpause"
      });
      expect(await auction.read.paused()).to.equal(false);
    });

    it("不允许非所有者暂停合约", async function (t) {
      const { auction, seller } = await deployAuctionFixture();

      const sellerAuction = await viem.getContractAt("NFTAuction", auction.address);

      try {
        await seller.writeContract({
          address: auction.address,
          abi: sellerAuction.abi,
          functionName: "pause"
        });
        t.fail("交易被拒绝");
      } catch (error: any) {
        expect(error.message).to.include("OwnableUnauthorizedAccount");
      }
    });
  });
});
