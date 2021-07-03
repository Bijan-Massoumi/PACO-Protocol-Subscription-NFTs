import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract } from 'ethers';
import { JsonRpcSigner } from '@ethersproject/providers';
import { network } from 'hardhat';
import '@nomiclabs/hardhat-waffle';
import fs from 'fs';
import { increaseTime, snapshotTime } from './test-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { first } from 'underscore';

const printNumber = (res: any) => {
  return (res as BigNumber).toNumber();
};

const interestRate = 2000;
const secondsInYear = 31536000;
const secondsInDay = 86400;
const oneRai = BigNumber.from('1000000000000000000');
let commonPartialContract: Contract;
let tokenContract: Contract;
let tokenSigner: JsonRpcSigner;
let owner: SignerWithAddress;
let addr1: SignerWithAddress;

const getBalance = async (signer: SignerWithAddress | JsonRpcSigner) => {
  return printNumber(
    await commonPartialContract.balanceOf(signer.getAddress())
  );
};

describe('Common Partial Ownership Contract', function () {
  before(async () => {
    [owner, addr1] = await ethers.getSigners();

    const myContractFactory = await ethers.getContractFactory(
      'CommonPartialSloths'
    );
    commonPartialContract = await myContractFactory.deploy(
      '0x03ab458634910aad20ef5f1c8ee96f1d6ac54919',
      interestRate
    );
    await commonPartialContract.deployed();
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0x5d3183cb8967e3c9b605dc35081e5778ee462328'],
    });

    tokenSigner = await ethers.provider.getSigner(
      '0x5d3183cb8967e3c9b605dc35081e5778ee462328'
    );
    let raiABI = fs.readFileSync('abis/erc20abi.Json', 'utf8');

    tokenContract = new Contract(
      '0x03ab458634910aad20ef5f1c8ee96f1d6ac54919',
      raiABI,
      tokenSigner
    );

    await tokenContract
      .connect(tokenSigner)
      .approve(commonPartialContract.address, oneRai.mul(10000));

    await tokenContract
      .connect(owner)
      .approve(commonPartialContract.address, oneRai.mul(10000));

    await tokenContract
      .connect(addr1)
      .approve(commonPartialContract.address, oneRai.mul(10000));

    await tokenContract
      .connect(tokenSigner)
      .transfer(owner.address, oneRai.mul(1000));
    await tokenContract
      .connect(tokenSigner)
      .transfer(addr1.address, oneRai.mul(1000));
    snapshotTime();
  });

  describe(`Testing Minting`, async () => {
    it('Can successfully mint a CPO Sloth', async function () {
      await commonPartialContract
        .connect(tokenSigner)
        .mintSloth(oneRai.mul(100), oneRai.mul(11));

      expect((await getBalance(tokenSigner)) === 1);
      const ownedTokens = await commonPartialContract.getTokenIdsForAddress(
        tokenSigner.getAddress()
      );

      expect(ownedTokens.length === 1);
      const tokenId = ownedTokens[0].toNumber();
      await increaseTime(5000);
      const res = (await commonPartialContract.getBond(tokenId)) as BigNumber;
      expect(res > oneRai.mul(10) && res < oneRai.mul(11));
    });

    it('Mint reverts with too little bond', async () => {
      await expect(
        commonPartialContract
          .connect(tokenSigner)
          .mintSloth(oneRai.mul(100), oneRai.mul(9))
      ).to.be.reverted;
    });
  });

  describe(`Testing altering stated price and bond`, async () => {
    let tokenId: number;
    before(async () => {
      const ownedTokens = await commonPartialContract.getTokenIdsForAddress(
        tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });

    it('Bond can be successfully increased', async () => {
      await commonPartialContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, oneRai.mul(2), 0);
      const bondAmount = await commonPartialContract.getBond(tokenId);
      expect(bondAmount < oneRai.mul(13) && bondAmount > oneRai.mul(12));
    });

    it('Bond can be decreased', async () => {
      await commonPartialContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, oneRai.mul(-2), 0);
      const res = await commonPartialContract.getBond(tokenId);
      expect(res > oneRai.mul(10) && res < oneRai.mul(11));
    });

    it('If bond decreases too much, tx reverts', async () => {
      await expect(
        commonPartialContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, oneRai.mul(-122), 0)
      ).to.be.reverted;
    });

    it(`Stated price can decrease and reverts when expected from increase`, async () => {
      await commonPartialContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, 0, oneRai.mul(-2));
      const res = await commonPartialContract.getPrice(tokenId);
      expect(res == oneRai.mul(98));
      await expect(
        commonPartialContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, 0, oneRai.mul(-99))
      ).to.be.revertedWith('bad values passed for delta values');
      await expect(
        commonPartialContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, 0, oneRai.mul(1009))
      ).to.be.revertedWith(
        'Cannot update price or bond unless > 10% of statedPrice is posted in bond.'
      );
    });
  });
  describe(`Interest is calculated as expected`, async () => {
    let tokenId: number;
    let interestThatShouldBeSubbed: BigNumber;
    before(async () => {
      const ownedTokens = await commonPartialContract.getTokenIdsForAddress(
        tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });
    it('interest is calculated correctly', async () => {
      const price = (await commonPartialContract.getPrice(
        tokenId
      )) as BigNumber;
      const bondBefore = (await commonPartialContract.getBond(
        tokenId
      )) as BigNumber;
      interestThatShouldBeSubbed = price.mul(interestRate).div(10000).div(12);
      await increaseTime(secondsInYear / 12);
      const bondAfter = (await commonPartialContract.getBond(
        tokenId
      )) as BigNumber;
      expect(
        bondBefore.sub(interestThatShouldBeSubbed).toString() ===
          bondAfter.toString()
      );
    });

    it('interest is reaped correctly', async () => {
      const interestBefore =
        await commonPartialContract.getInterestAccumulated();

      await commonPartialContract.reapInterestForTokenIds([tokenId]);

      const interestAfter =
        await commonPartialContract.getInterestAccumulated();

      expect(
        interestBefore
          .add(interestThatShouldBeSubbed)
          .div(10 ** 13)
          .toString() === interestAfter.div(10 ** 13).toString()
      );
    });
  });
  describe('NFT can be bought from another user', async () => {
    let tokenId: number;
    let bondBeforeBoughtOut: BigNumber;
    before(async () => {
      const ownedTokens = await commonPartialContract.getTokenIdsForAddress(
        tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });

    it('Owner can purchase token', async () => {
      const balanceBefore = await tokenContract.balanceOf(
        tokenSigner.getAddress()
      );

      bondBeforeBoughtOut = await commonPartialContract.getBond(tokenId);
      await commonPartialContract
        .connect(owner)
        .buyToken(tokenId, oneRai.mul(100), oneRai.mul(11));
      expect(commonPartialContract.balanceOf(tokenSigner.getAddress()) === 0);
      expect(commonPartialContract.ownerOf(tokenId) === owner.address);
      const balanceAfter = await tokenContract.balanceOf(
        tokenSigner.getAddress()
      );
      expect(
        balanceBefore.add(oneRai.mul(98)).toString() === balanceAfter.toString()
      );
    });

    it('Bond refund is available for previous holder', async () => {
      expect(
        (await commonPartialContract.viewBondRefund(tokenSigner.getAddress()))
          .div(10 ** 12)
          .toString() === bondBeforeBoughtOut.div(10 ** 12).toString()
      );
    });

    it('Bond can be claimed by previous holder', async () => {
      await expect(
        commonPartialContract.connect(tokenSigner).withdrawBondRefund()
      ).to.be.not.reverted;
    });
  });

  describe('Testing liquidation', async () => {
    let tokenId: number;
    let firstPrice: BigNumber;
    let depreciatedPrice: BigNumber;
    before(async () => {
      const ownedTokens = await commonPartialContract.getTokenIdsForAddress(
        owner.address
      );
      tokenId = ownedTokens[0].toNumber();
    });
    it('liquidationStartedAt is set', async () => {
      await increaseTime(6.602 * (secondsInYear / 12));
      const started = await commonPartialContract.getLiquidationStartedAt(
        tokenId
      );
      expect(started > 0);
      firstPrice = await commonPartialContract.getPrice(tokenId);
      const statedPrice = await commonPartialContract.getStatedPrice(tokenId);
      expect(firstPrice.toString() !== statedPrice.toString());
    });
    it('price halves after two days', async () => {
      await increaseTime(2 * secondsInDay);
      depreciatedPrice = await commonPartialContract.getPrice(tokenId);
      expect(depreciatedPrice < firstPrice.div(2));
    });

    it('NFT can be bought at discount', async () => {
      const balanceBefore = await tokenContract.balanceOf(addr1.address);
      await commonPartialContract
        .connect(addr1)
        .buyToken(tokenId, oneRai.mul(5), oneRai.mul(1));
      const balanceAfter = await tokenContract.balanceOf(addr1.address);

      expect(commonPartialContract.balanceOf(owner.address) === 0);
      expect(commonPartialContract.ownerOf(tokenId) === addr1.address);
      expect(
        balanceAfter < balanceBefore.sub(depreciatedPrice) &&
          balanceAfter > balanceBefore.sub(firstPrice)
      );
    });
  });
});
