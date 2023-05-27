import { ethers } from "ethers";
import { PacoExample__factory } from "../typechain/factories/PacoExample__factory";
import pinataSDK from "@pinata/sdk";
import fs from "fs";
import path from "path";
require('dotenv').config();

const RPC = process.env.RPC;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const PINATA_API_KEY = process.env.PINATA_API_KEY;
const PINATA_API_SECRET = process.env.PINATA_API_SECRET;

async function uploadMetadata() {
  const provider = new ethers.providers.JsonRpcProvider(RPC);
  if (!PRIVATE_KEY) {
    throw new Error("Private key not found in environment variable");
  }

  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const pacoFactory = PacoExample__factory.connect(CONTRACT_ADDRESS!, wallet);

  const pinata = new pinataSDK(PINATA_API_KEY, PINATA_API_SECRET);

  const readableStreamForFile = fs.createReadStream(path.resolve(__dirname, "./sampleimg.jpeg"));
  const uploadedImage = await pinata.pinFileToIPFS(readableStreamForFile,{
    pinataMetadata: {
      name: "Paco",
    },
  });
  const imageUri = `https://gateway.pinata.cloud/ipfs/${uploadedImage.IpfsHash}`;

  const totalSupply = await pacoFactory.totalSupply();

  for (let i = 0; i < totalSupply.toNumber(); i++) {
    const tokenId = await pacoFactory.tokenByIndex(i);
    await pacoFactory.setTokenURI(tokenId, imageUri,{
      gasLimit: 1000000,
    });
    console.log(`Metadata for token #${tokenId} has been updated.`);
  }
}

uploadMetadata();
