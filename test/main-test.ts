import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract } from 'ethers';
import { JsonRpcSigner } from '@ethersproject/providers';
import { network } from 'hardhat';
import '@nomiclabs/hardhat-waffle';
import { fstat } from 'fs';
import fs from 'fs';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const printNumber = (res: any) => {
  return (res as BigNumber).toNumber();
};

const oneRai = BigNumber.from('1000000000000000000');
let commonPartialContract: Contract;
let raiContract: Contract;
let raiSigner: JsonRpcSigner;
let owner: SignerWithAddress;
let addr1: SignerWithAddress;

const getBalance = async (signer: SignerWithAddress | JsonRpcSigner) => {
  return printNumber(
    await commonPartialContract.balanceOf(signer.getAddress())
  );
};

const increaseTime = async (amount: number) => {
  await network.provider.send('evm_increaseTime', [amount]);
  await network.provider.send('evm_mine');
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

    raiSigner = await ethers.provider.getSigner(
      '0x5d3183cb8967e3c9b605dc35081e5778ee462328'
    );
    let raiABI = fs.readFileSync('abis/erc20abi.Json', 'utf8');

    raiContract = new Contract(
      '0x03ab458634910aad20ef5f1c8ee96f1d6ac54919',
      raiABI,
      raiSigner
    );

    await raiContract
      .connect(raiSigner)
      .approve(commonPartialContract.address, oneRai.mul(10000));

    await raiContract
      .connect(owner)
      .approve(commonPartialContract.address, oneRai.mul(10000));

    await raiContract
      .connect(addr1)
      .approve(commonPartialContract.address, oneRai.mul(10000));

    await raiContract
      .connect(raiSigner)
      .transfer(owner.address, oneRai.mul(1000));
    await raiContract
      .connect(raiSigner)
      .transfer(addr1.address, oneRai.mul(1000));
  });

  describe(`Testing Minting`, async () => {
    it('Can successfully mint a CPO Sloth', async function () {
      await commonPartialContract
        .connect(raiSigner)
        .mintSloth(oneRai.mul(100), oneRai.mul(11));

      expect((await getBalance(raiSigner)) === 1);
      const ownedTokens = await commonPartialContract.getTokenIdsForAddress(
        raiSigner.getAddress()
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
          .connect(raiSigner)
          .mintSloth(oneRai.mul(100), oneRai.mul(9))
      ).to.be.reverted;
    });
  });
});
