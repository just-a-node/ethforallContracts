require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  networks: {
    hardhat: {
      forking: {
        url: process.env.ALCHEMY_GOERLI_API_URL, // goerli testnet
        blockNumber: 8439100
      }
    },
    goerli: {
      url: process.env.ALCHEMY_GOERLI_API_URL,
      accounts: [process.env.PRIVATE_KEY]
    },
    mumbai: {
      url: process.env.ALCHEMY_MUMBAI_API_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY
  },
  polygonscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY
  }
};
