import { ethers } from "ethers";
import { wethAddress } from "./common";

// Replace with the actual contract address
const PACO_ADDRESS = "0x0E51BB947712537575621379b88665061A122B55";

const RPC = process.env.RPC;

async function approveTokenTransfer(wallet: ethers.Wallet) {
  const contractABI = [
    "function approve(address spender, uint256 amount) public returns (bool)",
    "function allowance(address owner, address spender) public view returns (uint256)",
  ];

  const tokenContract = new ethers.Contract(wethAddress, contractABI, wallet);
  const spenderAddress = PACO_ADDRESS;
  const amountToApprove = ethers.utils.parseUnits("101", 18);
  const allowance = await tokenContract.allowance(
    wallet.address,
    spenderAddress
  );
  if (allowance.gte(amountToApprove)) {
    console.log(
      `Wallet has already approved ${amountToApprove.toString()} tokens for spender: ${spenderAddress}, wallet:${
        wallet.address
      }`
    );
    return;
  }

  const approveTx = await tokenContract.approve(
    spenderAddress,
    amountToApprove
  );
  await approveTx.wait();

  console.log(
    `Approved ${amountToApprove.toString()} tokens for  spender: ${spenderAddress}, wallet: ${
      wallet.address
    }`
  );
}

// Example usage:
async function run() {
  const pk1 = process.env.ACCOUNT1;
  const pk2 = process.env.ACCOUNT2;

  if (!pk1 || !pk2) {
    throw new Error("test pks not found in environment variables");
  }

  const provider = new ethers.providers.JsonRpcProvider(RPC);

  const accnt1 = new ethers.Wallet(pk1, provider);
  await approveTokenTransfer(accnt1);

  const accnt2 = new ethers.Wallet(pk2, provider);
  await approveTokenTransfer(accnt2);
}

run();
