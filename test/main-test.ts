import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract } from 'ethers';
import { JsonRpcSigner } from '@ethersproject/providers';
import { network } from 'hardhat';
import '@nomiclabs/hardhat-waffle';
import fs from 'fs';
import { increaseTime, snapshotTime } from './test-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import SphinxesArtifact from '../artifacts/contracts/Sphinxes.sol/Sphinxes.json';
import { Sphinxes } from '../typechain/Sphinxes';
import { Treasury } from '../typechain/Treasury';

const printNumber = (res: any) => {
  return (res as BigNumber).toNumber();
};

const interestRate = 2000;
const secondsInYear = 31536000;
const secondsInDay = 86400;
const oneRai = BigNumber.from('1000000000000000000');
const tokenAddress = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
let sphinxContract: Sphinxes;
let treasuryContract: Treasury;
let tokenContract: Contract;
let tokenSigner: JsonRpcSigner;
let owner: SignerWithAddress;
let addr1: SignerWithAddress;
let attributeProbs = [[65535], [65535], [65535], [65535], [65535], [65535]];

const getBalance = async (signer: SignerWithAddress | JsonRpcSigner) => {
  return printNumber(await sphinxContract.balanceOf(await signer.getAddress()));
};

describe('Common Partial Ownership Contract', function () {
  before(async () => {
    [owner, addr1] = await ethers.getSigners();

    const myContractFactory = await ethers.getContractFactory('Sphinxes');
    const treasuryContractFactory = await ethers.getContractFactory('Treasury');
    treasuryContract = (await treasuryContractFactory.deploy()) as Treasury;

    sphinxContract = (await myContractFactory.deploy(
      tokenAddress,
      treasuryContract.address,
      interestRate,
      ...attributeProbs
    )) as Sphinxes;
    await sphinxContract.deployed();
    await treasuryContract.initialize(sphinxContract.address, tokenAddress);
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0x422162745B12b8c58D19E348d7c8c134BBeDF886'],
    });

    tokenSigner = await ethers.provider.getSigner(
      '0x422162745B12b8c58D19E348d7c8c134BBeDF886'
    );

    sphinxContract.setSaleStatus(true);

    let erc20Abi = fs.readFileSync('abis/erc20abi.Json', 'utf8');

    tokenContract = new Contract(tokenAddress, erc20Abi, tokenSigner);
    await tokenContract
      .connect(tokenSigner)
      .approve(sphinxContract.address, oneRai.mul(10000));
    await tokenContract
      .connect(owner)
      .approve(sphinxContract.address, oneRai.mul(10000));
    await tokenContract
      .connect(addr1)
      .approve(sphinxContract.address, oneRai.mul(10000));
    await tokenContract
      .connect(tokenSigner)
      .transfer(owner.address, oneRai.mul(500));

    await tokenContract
      .connect(tokenSigner)
      .transfer(addr1.address, oneRai.mul(500));
    snapshotTime();
  });

  describe(`Testing Minting`, async () => {
    it('Can successfully mint a CPO Sloth', async function () {
      await sphinxContract
        .connect(tokenSigner)
        .mintSphinx(1, oneRai.mul(100), oneRai.mul(11));

      expect((await getBalance(tokenSigner)) === 1);
      const ownedTokens = await sphinxContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );

      expect(ownedTokens.length === 1);
      const tokenId = ownedTokens[0].toNumber();
      await increaseTime(5000);
      const res = (await sphinxContract.getBond(tokenId)) as BigNumber;
      expect(res > oneRai.mul(10) && res < oneRai.mul(11));
    });

    it('Mint reverts with too little bond', async () => {
      await expect(
        sphinxContract
          .connect(tokenSigner)
          .mintSphinx(1, oneRai.mul(100), oneRai.mul(9))
      ).to.be.reverted;
    });
  });

  describe(`Testing altering stated price and bond`, async () => {
    let tokenId: number;
    before(async () => {
      const ownedTokens = await sphinxContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });

    it('Bond can be successfully increased', async () => {
      await sphinxContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, oneRai.mul(2), 0);
      const bondAmount = await sphinxContract.getBond(tokenId);
      expect(bondAmount < oneRai.mul(13) && bondAmount > oneRai.mul(12));
    });

    it('Bond can be decreased', async () => {
      await sphinxContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, oneRai.mul(-2), 0);
      const res = await sphinxContract.getBond(tokenId);
      expect(res > oneRai.mul(10) && res < oneRai.mul(11));
    });

    it('If bond decreases too much, tx reverts', async () => {
      await expect(
        sphinxContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, oneRai.mul(-122), 0)
      ).to.be.reverted;
    });

    it(`Stated price can decrease and reverts when expected from increase`, async () => {
      await sphinxContract
        .connect(tokenSigner)
        .alterStatedPriceAndBond(tokenId, 0, oneRai.mul(-2));
      const res = await sphinxContract.getPrice(tokenId);
      expect(res == oneRai.mul(98));
      await expect(
        sphinxContract
          .connect(tokenSigner)
          .alterStatedPriceAndBond(tokenId, 0, oneRai.mul(-99))
      ).to.be.revertedWith('bad values passed for delta values');
      await expect(
        sphinxContract
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
      const ownedTokens = await sphinxContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });
    it('interest is calculated correctly', async () => {
      const price = (await sphinxContract.getPrice(tokenId)) as BigNumber;
      const bondBefore = (await sphinxContract.getBond(tokenId)) as BigNumber;
      interestThatShouldBeSubbed = price.mul(interestRate).div(10000).div(12);
      await increaseTime(secondsInYear / 12);
      const bondAfter = (await sphinxContract.getBond(tokenId)) as BigNumber;
      expect(
        bondBefore.sub(interestThatShouldBeSubbed).toString() ===
          bondAfter.toString()
      );
    });

    it('interest is reaped correctly', async () => {
      const interestBefore = await tokenContract.balanceOf(
        treasuryContract.address
      );

      await sphinxContract.reapInterestForTokenIds([tokenId]);

      const interestAfter = await tokenContract.balanceOf(
        treasuryContract.address
      );

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
      const ownedTokens = await sphinxContract.getTokenIdsForAddress(
        await tokenSigner.getAddress()
      );
      tokenId = ownedTokens[0].toNumber();
    });

    it('Owner can purchase token', async () => {
      const balanceBefore = await tokenContract.balanceOf(
        tokenSigner.getAddress()
      );

      bondBeforeBoughtOut = await sphinxContract.getBond(tokenId);
      await sphinxContract
        .connect(owner)
        .buyToken(tokenId, oneRai.mul(100), oneRai.mul(11));
      expect(
        (await sphinxContract.balanceOf(await tokenSigner.getAddress())) ===
          BigNumber.from(0)
      );
      expect((await sphinxContract.ownerOf(tokenId)) === owner.address);
      const balanceAfter = await tokenContract.balanceOf(
        tokenSigner.getAddress()
      );
      expect(
        balanceBefore.add(oneRai.mul(98)).toString() === balanceAfter.toString()
      );
    });

    it('Bond refund is available for previous holder', async () => {
      expect(
        (await sphinxContract.viewBondRefund(await tokenSigner.getAddress()))
          .div(10 ** 12)
          .toString() === bondBeforeBoughtOut.div(10 ** 12).toString()
      );
    });

    it('Bond can be claimed by previous holder', async () => {
      await expect(sphinxContract.connect(tokenSigner).withdrawBondRefund()).to
        .be.not.reverted;
    });
  });

  describe('Testing liquidation', async () => {
    let tokenId: number;
    let firstPrice: BigNumber;
    let depreciatedPrice: BigNumber;
    before(async () => {
      const ownedTokens = await sphinxContract.getTokenIdsForAddress(
        owner.address
      );
      tokenId = ownedTokens[0].toNumber();
    });
    it('liquidationStartedAt is set', async () => {
      await increaseTime(6.602 * (secondsInYear / 12));
      const started = await sphinxContract.getLiquidationStartedAt(tokenId);
      expect(started > BigNumber.from(0));
      firstPrice = await sphinxContract.getPrice(tokenId);
      const statedPrice = await sphinxContract.getStatedPrice(tokenId);
      expect(firstPrice.toString() !== statedPrice.toString());
    });
    it('price halves after two days', async () => {
      await increaseTime(2 * secondsInDay);
      depreciatedPrice = await sphinxContract.getPrice(tokenId);
      expect(depreciatedPrice < firstPrice.div(2));
    });

    it('NFT can be bought at discount', async () => {
      const balanceBefore = await tokenContract.balanceOf(addr1.address);
      await sphinxContract
        .connect(addr1)
        .buyToken(tokenId, oneRai.mul(5), oneRai.mul(1));
      const balanceAfter = await tokenContract.balanceOf(addr1.address);

      expect(
        (await sphinxContract.balanceOf(owner.address)) === BigNumber.from(0)
      );
      expect((await sphinxContract.ownerOf(tokenId)) === addr1.address);
      expect(
        balanceAfter < balanceBefore.sub(depreciatedPrice) &&
          balanceAfter > balanceBefore.sub(firstPrice)
      );
    });
  });
});
