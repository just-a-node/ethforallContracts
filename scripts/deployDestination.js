// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

  const DestinationPool = await hre.ethers.getContractFactory("DestinationPool");
  const destinationPool = await DestinationPool.deploy("0xA549Bd62BBD6C1110Bc4e63999D958B848E9F0a2");

  await destinationPool.deployed();

  console.log(
    `DestinationPool Deployed to ${destinationPool.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
