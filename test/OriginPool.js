const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");

const logger = (context, log) => {
    console.log("----------------------------------------------");
    console.log(`Logging for : ${context}`);
    console.log(log);
    console.log("----------------------------------------------");
}

describe ('OriginPool Contract', function () {
    const deployOriginPool = async () => {
        const [account1, account2] = await ethers.getSigners();
        const OriginPool = await ethers.getContractFactory("OriginPool");
        const originPool = await OriginPool.deploy(); // the constructor values are hardcoded
        await originPool.deployed();
        return {originPool, account1, account2};
    }

    it ("Deploying OriginPool Contract", async function() {
        const {originPool, account1} = await loadFixture(deployOriginPool);
        logger("Address of Deployer's account", account1.address);
        logger("Contract address ", originPool.address);
    })
})