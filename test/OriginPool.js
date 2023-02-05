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
    it ("Deploying OriginPool Contract", async function() {
        const [owner, otherAccount] = await ethers.getSigners();
        logger('OriginPool contract Deploying address', owner.address);

        const OriginPool = await ethers.getContractFactory("OriginPool");
        const originPool = await OriginPool.deploy(); // the constructor values are hardcoded
        await originPool.deployed();
        logger("Contract address ", originPool.address);
    })
})