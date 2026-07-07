import { ethers } from "hardhat";
import fs from "fs";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "ETH");

  const AlloyLaunchpad = await ethers.getContractFactory("AlloyLaunchpad");
  const launchpad = await AlloyLaunchpad.deploy();
  await launchpad.waitForDeployment();
  const launchpadAddr = await launchpad.getAddress();
  console.log("AlloyLaunchpad:", launchpadAddr);

  const AlloyKeeper = await ethers.getContractFactory("AlloyKeeper");
  const keeper = await AlloyKeeper.deploy(launchpadAddr);
  await keeper.waitForDeployment();
  const keeperAddr = await keeper.getAddress();
  console.log("AlloyKeeper:", keeperAddr);

  const out = { network: "robinhood", chainId: 4663, AlloyLaunchpad: launchpadAddr, AlloyKeeper: keeperAddr, deployer: deployer.address };
  fs.mkdirSync("deployments/robinhood", { recursive: true });
  fs.writeFileSync("deployments/robinhood/addresses.json", JSON.stringify(out, null, 2));
  console.log("Saved to deployments/robinhood/addresses.json");
}
main().catch((e) => { console.error(e); process.exit(1); });


