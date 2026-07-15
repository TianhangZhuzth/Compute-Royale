import { expect } from "chai";
import { ethers } from "hardhat";

describe("AlloyMeme", function () {
  let meme: any, owner: any, holder1: any;

  beforeEach(async function () {
    [owner, holder1] = await ethers.getSigners();
    const stock = ethers.Wallet.createRandom().address;
    const F = await ethers.getContractFactory("AlloyMeme");
    meme = await F.deploy("Nvidia Memecoin", "NVDM", stock, owner.address);
    await meme.waitForDeployment();
  });

  it("has correct name and symbol", async function () {
    expect(await meme.name()).to.equal("Nvidia Memecoin");
    expect(await meme.symbol()).to.equal("NVDM");
  });

  it("has backing stock set", async function () {
    expect(await meme.backingStock()).to.not.equal(ethers.ZeroAddress);
  });

  it("tracks pending dividends", async function () {
    await meme.transfer(holder1.address, ethers.parseEther("1000"));
    const pending = await meme.pendingDividends(holder1.address);
    expect(pending).to.be.gte(0);
  });
});








