import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Sepolia Chainlink Price Feed Addresses
 * ETH/USD: 0x694AA1769357215DE4FAC081bf1f309aDC325306
 * LINK/USD: 0xc59E3633BAAC79493d908e63626716e204A45EdF
 * USDC/USD: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
 */

const NFTAuctionDeploymentModule = buildModule("NFTAuctionDeployment", (m) => {
  // Deploy parameters
  const ethUsdPriceFeed = m.getParameter(
    "ethUsdPriceFeed",
    "0x694AA1769357215DE4FAC081bf1f309aDC325306" // Sepolia ETH/USD
  );
  const feeRecipient = m.getParameter(
    "feeRecipient",
    "0x0000000000000000000000000000000000000000" // Will be set to deployer
  );
  const platformFeePercent = m.getParameter("platformFeePercent", 250n); // 2.5%

  // Deploy NFT contract
  const nft = m.contract("NFT", ["NFT Auction Collection", "NAC", ""]);

  // Deploy PriceOracle contract
  const priceOracle = m.contract("PriceOracle", [ethUsdPriceFeed]);

  // Deploy NFTAuction contract
  const auction = m.contract("NFTAuction", [], {
    afterDeploy: async (contract, deployment) => {
      await contract.write.initialize([
        priceOracle,
        feeRecipient,
        platformFeePercent,
      ]);
    },
  });

  return {
    nft,
    priceOracle,
    auction,
  };
});

export default NFTAuctionDeploymentModule;