import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract } from 'ethers';
import { JsonRpcSigner } from '@ethersproject/providers';
import { network } from 'hardhat';
import '@nomiclabs/hardhat-waffle';
import fs from 'fs';
import { increaseTime } from './test-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const printNumber = (res: any) => {
  return (res as BigNumber).toNumber();
};

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
      '0x03ab458634910aad20ef5f1c8ee96f1d6ac54919'
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
  });
});
