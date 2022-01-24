import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { JsonRpcSigner } from "@ethersproject/providers";
import { network } from "hardhat";
import "@nomiclabs/hardhat-waffle";
import fs from "fs";
import { increaseTime, snapshotTime } from "./test-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { PaCoExample } from "../typechain/PaCoExample";
import { Treasury } from "../typechain/Treasury";

const printNumber = (res: any) => {
  return (res as BigNumber).toNumber();
};

const wethWhale = "0xbecaa4ad36e5d134fd6979cc6780eb48ac5b5a93";
const feeRate = 2000;
const secondsInYear = 31536000;
const secondsInDay = 86400;
const oneETH = BigNumber.from("1000000000000000000");
const tokenAddress = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
let paCoContract: PaCoExample;
let treasuryContract: Treasury;
let tokenContract: Contract;
let tokenSigner: JsonRpcSigner;
let owner: SignerWithAddress;
let addr1: SignerWithAddress;

const getBalance = async (signer: SignerWithAddress | JsonRpcSigner) => {
  return printNumber(await paCoContract.balanceOf(await signer.getAddress()));
};

describe("PaCo Contract Suite", function () {
  before(async () => {
    [owner, addr1] = await ethers.getSigners();

    const paCoFactory = await ethers.getContractFactory("PaCoExample");
    const treasuryContractFactory = await ethers.getContractFactory("Treasury");
    treasuryContract = (await treasuryContractFactory.deploy(
      tokenAddress
    )) as Treasury;

    paCoContract = (await paCoFactory.deploy(
      tokenAddress,
      treasuryContract.address,
      feeRate
    )) as PaCoExample;

    await paCoContract.deployed();

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [wethWhale],
    });

    tokenSigner = await ethers.provider.getSigner(wethWhale);

    paCoContract.setSaleStatus(true);

    let erc20Abi = fs.readFileSync("abis/erc20abi.Json", "utf8");

    tokenContract = new Contract(tokenAddress, erc20Abi, tokenSigner);
    await tokenContract
      .connect(tokenSigner)
      .approve(paCoContract.address, oneETH.mul(10000));
    await tokenContract
      .connect(owner)
      .approve(paCoContract.address, oneETH.mul(10000));

    await tokenContract
      .connect(addr1)
      .approve(paCoContract.address, oneETH.mul(10000));

    await tokenContract
      .connect(tokenSigner)
      .transfer(owner.address, oneETH.mul(500));

    await tokenContract
      .connect(tokenSigner)
      .transfer(addr1.address, oneETH.mul(500));

    console.log("here");
    snapshotTime();
  });

  describe(`Testing Minting`, async () => {
    it("Can successfully mint a PaCo NFT", async function () {
      await paCoContract
        .connect(tokenSigner)
        .mint(1, oneETH.mul(100), oneETH.mul(11));

      expect((await getBalance(tokenSigner)) === 1);
      const ownedTokens = await paCoContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );

      expect(ownedTokens.length === 1);
      const tokenId = ownedTokens[0].toNumber();
      await increaseTime(5000);
      const res = (await paCoContract.getBond(tokenId)) as BigNumber;
      expect(res > oneETH.mul(10) && res < oneETH.mul(11));
    });

    it("Mint reverts with too little bond", async () => {
      await expect(
        paCoContract
          .connect(tokenSigner)
          .mint(1, oneETH.mul(100), oneETH.mul(9))
      ).to.be.reverted;
    });
  });

  describe(`Testing altering stated price and bond`, async () => {
    let tokenId: number;
    before(async () => {
      const ownedTokens = await paCoContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });

    it("Bond can be successfully increased", async () => {
      await paCoContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, oneETH.mul(2), 0);
      const bondAmount = await paCoContract.getBond(tokenId);
      expect(bondAmount < oneETH.mul(13) && bondAmount > oneETH.mul(12));
    });

    it("Bond can be decreased", async () => {
      await paCoContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, oneETH.mul(-2), 0);
      const res = await paCoContract.getBond(tokenId);
      expect(res > oneETH.mul(10) && res < oneETH.mul(11));
    });

    it("If bond decreases too much, tx reverts", async () => {
      await expect(
        paCoContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, oneETH.mul(-122), 0)
      ).to.be.reverted;
    });

    it(`Stated price can decrease and reverts when expected from increase`, async () => {
      await paCoContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, 0, oneETH.mul(-2));
      const res = await paCoContract.getPrice(tokenId);
      expect(res == oneETH.mul(98));
      await expect(
        paCoContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, 0, oneETH.mul(-99))
      ).to.be.revertedWith("bad values passed for delta values");
      await expect(
        paCoContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, 0, oneETH.mul(1009))
      ).to.be.revertedWith("Insufficient bond");
    });
  });
  describe(`Fee is calculated as expected`, async () => {
    let tokenId: number;
    let feeThatShouldBeSubbed: BigNumber;
    before(async () => {
      const ownedTokens = await paCoContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });
    it("fee is calculated correctly", async () => {
      const price = (await paCoContract.getPrice(tokenId)) as BigNumber;
      const bondBefore = (await paCoContract.getBond(tokenId)) as BigNumber;
      feeThatShouldBeSubbed = price.mul(feeRate).div(10000).div(12);
      await increaseTime(secondsInYear / 12);
      const bondAfter = (await paCoContract.getBond(tokenId)) as BigNumber;
      expect(
        bondBefore.sub(feeThatShouldBeSubbed).toString() ===
          bondAfter.toString()
      );
    });

    it("fee is reaped correctly", async () => {
      const feeBefore = await tokenContract.balanceOf(treasuryContract.address);

      await paCoContract.reapSafForTokenIds([tokenId]);

      const feeAfter = await tokenContract.balanceOf(treasuryContract.address);

      expect(
        feeBefore
          .add(feeThatShouldBeSubbed)
          .div(10 ** 13)
          .toString() === feeAfter.div(10 ** 13).toString()
      );
    });
  });
  describe("NFT can be bought from another user", async () => {
    let tokenId: number;
    let bondBeforeBoughtOut: BigNumber;
    before(async () => {
      const ownedTokens = await paCoContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });

    it("Owner can purchase token", async () => {
      const balanceBefore = await tokenContract.balanceOf(
        tokenSigner.getAddress()
      );

      bondBeforeBoughtOut = await paCoContract.getBond(tokenId);
      await paCoContract
        .connect(owner)
        .buyToken(tokenId, oneETH.mul(100), oneETH.mul(11));
      expect(
        (await paCoContract.balanceOf(await tokenSigner.getAddress())) ===
          BigNumber.from(0)
      );
      expect((await paCoContract.ownerOf(tokenId)) === owner.address);
      const balanceAfter = await tokenContract.balanceOf(
        tokenSigner.getAddress()
      );
      expect(
        balanceBefore.add(oneETH.mul(98)).toString() === balanceAfter.toString()
      );
    });

    it("Bond refund is available for previous holder", async () => {
      expect(
        (await paCoContract.viewBondRefund(await tokenSigner.getAddress()))
          .div(10 ** 12)
          .toString() === bondBeforeBoughtOut.div(10 ** 12).toString()
      );
    });

    it("Bond can be claimed by previous holder", async () => {
      await expect(paCoContract.connect(tokenSigner).withdrawBondRefund()).to.be
        .not.reverted;
    });
  });

  describe("Testing liquidation", async () => {
    let tokenId: number;
    let firstPrice: BigNumber;
    let depreciatedPrice: BigNumber;
    before(async () => {
      const ownedTokens = await paCoContract.getTokenIdsForAddress(
        owner.address
      );
      tokenId = ownedTokens[0].toNumber();
    });
    it("liquidationStartedAt is set", async () => {
      await increaseTime(6.602 * (secondsInYear / 12));
      const started = await paCoContract.getLiquidationStartedAt(tokenId);
      expect(started > BigNumber.from(0));
      firstPrice = await paCoContract.getPrice(tokenId);
      const statedPrice = await paCoContract.getStatedPrice(tokenId);
      expect(firstPrice.toString() !== statedPrice.toString());
    });
    it("price halves after two days", async () => {
      await increaseTime(2 * secondsInDay);
      depreciatedPrice = await paCoContract.getPrice(tokenId);
      expect(depreciatedPrice < firstPrice.div(2));
    });

    it("NFT can be bought at discount", async () => {
      const balanceBefore = await tokenContract.balanceOf(addr1.address);
      await paCoContract
        .connect(addr1)
        .buyToken(tokenId, oneETH.mul(5), oneETH.mul(1));
      const balanceAfter = await tokenContract.balanceOf(addr1.address);

      expect(
        (await paCoContract.balanceOf(owner.address)) === BigNumber.from(0)
      );
      expect((await paCoContract.ownerOf(tokenId)) === addr1.address);
      expect(
        balanceAfter < balanceBefore.sub(depreciatedPrice) &&
          balanceAfter > balanceBefore.sub(firstPrice)
      );
    });
  });

  describe(`Testing transfer`, async () => {
    let tokenId: number;
    before(async () => {
      const ownedTokens = await paCoContract.getTokenIdsForAddress(
        addr1.address
      );
      tokenId = ownedTokens[0].toNumber();
    });
    it(`transfer fails`, async () => {
      await expect(
        paCoContract
          .connect(addr1)
          .transferFrom(addr1.address, await tokenSigner.getAddress(), tokenId)
      ).to.be.revertedWith("Intent to receive expired.");
    });
    it("Can signal intent to receive", async () => {
      const block = await ethers.provider.getBlock(
        await ethers.provider.getBlockNumber()
      );
      const currTime = block.timestamp;
      await paCoContract
        .connect(tokenSigner)
        .setEscrowIntent(
          tokenId,
          oneETH.mul(5),
          oneETH.mul(1),
          currTime + 100000
        );
      const res = await paCoContract.getIntent(
        tokenId,
        await tokenSigner.getAddress()
      );
      expect(res.expiry.toNumber()).equal(currTime + 100000);
    });
    it("Can transfer ownership", async () => {
      await paCoContract
        .connect(addr1)
        .transferFrom(addr1.address, await tokenSigner.getAddress(), tokenId);
      expect(await paCoContract.ownerOf(tokenId)).equal(
        await tokenSigner.getAddress()
      );
    });
  });
});
