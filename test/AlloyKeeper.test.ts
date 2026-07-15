import { expect } from "chai";
import { ethers } from "hardhat";

describe("AlloyKeeper", function () {
  let keeper: any, launchpad: any, owner: any;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();
    const L = await ethers.getContractFactory("AlloyLaunchpad");
    launchpad = await L.deploy();
    await launchpad.waitForDeployment();
    const K = await ethers.getContractFactory("AlloyKeeper");
    keeper = await K.deploy(await launchpad.getAddress());
    await keeper.waitForDeployment();
  });

  it("links to correct launchpad", async function () {
    expect(await keeper.launchpad()).to.equal(await launchpad.getAddress());
  });

  it("returns empty pending list initially", async function () {
    const pending = await keeper.getPendingCoins();
    expect(pending.length).to.equal(0);
  });

  it("owner can set interval", async function () {
    const tx = await keeper.setInterval(1800);
    await tx.wait();
    expect(await keeper.interval()).to.equal(1800);
  });
});








