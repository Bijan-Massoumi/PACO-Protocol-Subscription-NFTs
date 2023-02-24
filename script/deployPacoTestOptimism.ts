import { ethers } from "ethers";
import { PaCoExample__factory } from "../typechain/factories/PaCoExample__factory";
import { wethAddress } from "./common";

const RPC = process.env.RPC;
const PRIVATE_KEY = process.env.DEPLOYMENT_PRIVATE_KEY;

async function deployContract() {
  const provider = new ethers.providers.JsonRpcProvider(RPC);
  if (!PRIVATE_KEY) {
    throw new Error("Private key not found in environment variable");
  }

  const withdrawAddress = "0xc871329DDD39FebB626bB6B4FD75fEa04295a089";
  // 20% annual fee rate
  const selfAssessmentRate = 2000;

  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const pacoFactory = new PaCoExample__factory(wallet);
  const contract = await pacoFactory.deploy(
    wethAddress,
    withdrawAddress,
    selfAssessmentRate,
    {
      gasLimit: 5000000, // replace with your desired gas limit
    }
  );
  await contract.deployed();

  console.log(`Contract deployed at address: ${contract.address}`);
}

deployContract();
