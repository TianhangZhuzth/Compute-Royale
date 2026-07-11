import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();
const PK = process.env.PRIVATE_KEY || "0x" + "0".repeat(64);
const config: HardhatUserConfig = {
  solidity: { version: "0.8.26", settings: { optimizer: { enabled: true, runs: 200 }, viaIR: true } },
  networks: {
    robinhood: { url: process.env.RPC_URL || "https://mainnet.robinhoodchain.io", chainId: 4663, accounts: [PK] },
    hardhat: { chainId: 31337 }
  },
  gasReporter: { enabled: process.env.REPORT_GAS === "true", currency: "USD" }
};
export default config;





