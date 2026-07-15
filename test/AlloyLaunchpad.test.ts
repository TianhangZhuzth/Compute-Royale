import { expect } from "chai";
import { ethers } from "hardhat";

describe("AlloyLaunchpad", function () {
  let launchpad: any, owner: any, user: any;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();
    const F = await ethers.getContractFactory("AlloyLaunchpad");
    launchpad = await F.deploy();
    await launchpad.waitForDeployment();
  });

  it("deploys with correct owner", async function () {
    expect(await launchpad.owner()).to.equal(owner.address);
  });

  it("has zero coins at start", async function () {
    expect(await launchpad.coinCount()).to.equal(0);
  });

  it("creates coin with backing stock", async function () {
    const stock = ethers.Wallet.createRandom().address;
    const tx = await launchpad.connect(user).launch("Nvidia Memecoin", "NVDM", stock, { value: ethers.parseEther("0.1") });
    await tx.wait();
    expect(await launchpad.coinCount()).to.equal(1);
    const coin = await launchpad.getCoin(0);
    expect(coin.backingStock).to.equal(stock);
  });

  it("reverts if fee not met", async function () {
    await expect(launchpad.launch("Test", "TST", ethers.ZeroAddress)).to.be.revertedWith("insufficient fee");
  });
});








