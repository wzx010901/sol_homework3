import { expect } from "chai";
import { network } from "hardhat";
import { getAddress, parseEther } from "viem";
import { describe, it } from "node:test";

describe("NFT 合约", async function () {
  const { viem } = await network.connect();

  async function deployNFTFixture() {
    const [owner, addr1, addr2] = await viem.getWalletClients();
    const publicClient = await viem.getPublicClient();

    const nft = await viem.deployContract("NFT", [
      "Test NFT",
      "TNFT",
      "https://api.example.com/metadata/",
    ]);

    return {
      viem,
      nft,
      owner,
      addr1,
      addr2,
      publicClient,
    };
  }

  describe("部署", function () {
    it("设置正确的名称和符号", async function () {
      const { nft } = await deployNFTFixture();

      expect(await nft.read.name()).to.equal("Test NFT");
      expect(await nft.read.symbol()).to.equal("TNFT");
    });

    it("设置正确的所有者", async function () {
      const { nft, owner } = await deployNFTFixture();

      expect(await nft.read.owner()).to.equal(getAddress(owner.account.address));
    });
  });

  describe("铸造", function () {
    it("铸造新代币", async function () {
      const { nft, addr1, publicClient } = await deployNFTFixture();

      const tx = await nft.write.mint([addr1.account.address, "token-uri-1"]);
      await publicClient.waitForTransactionReceipt({ hash: tx });

      expect(await nft.read.balanceOf([addr1.account.address])).to.equal(1n);
      expect(await nft.read.ownerOf([0n])).to.equal(getAddress(addr1.account.address));
      expect(await nft.read.tokenURI([0n])).to.equal("https://api.example.com/metadata/token-uri-1");
    });

    it("允许所有者铸造多个代币", async function () {
      const { nft, addr1, addr2, publicClient } = await deployNFTFixture();

      const tx1 = await nft.write.mint([addr1.account.address, "token-uri-1"]);
      await publicClient.waitForTransactionReceipt({ hash: tx1 });

      const tx2 = await nft.write.mint([addr2.account.address, "token-uri-2"]);
      await publicClient.waitForTransactionReceipt({ hash: tx2 });

      expect(await nft.read.balanceOf([addr1.account.address])).to.equal(1n);
      expect(await nft.read.balanceOf([addr2.account.address])).to.equal(1n);
      expect(await nft.read.ownerOf([0n])).to.equal(getAddress(addr1.account.address));
      expect(await nft.read.ownerOf([1n])).to.equal(getAddress(addr2.account.address));
    });
  });

  describe("转移", function () {
    it("在账户之间转移代币", async function () {
      const { nft, addr1, addr2, publicClient } = await deployNFTFixture();

      const mintTx = await nft.write.mint([addr1.account.address, "token-uri-1"]);
      await publicClient.waitForTransactionReceipt({ hash: mintTx });

      const transferTx = await nft.write.transferFrom(
        [addr1.account.address, addr2.account.address, 0n],
        { account: addr1.account }
      );
      await publicClient.waitForTransactionReceipt({ hash: transferTx });

      expect(await nft.read.ownerOf([0n])).to.equal(getAddress(addr2.account.address));
      expect(await nft.read.balanceOf([addr1.account.address])).to.equal(0n);
      expect(await nft.read.balanceOf([addr2.account.address])).to.equal(1n);
    });
  });
});
