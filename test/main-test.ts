const { expect } = require('chai');
import { ethers } from 'hardhat';
import { BigNumber, Signer } from 'ethers';
import { network } from 'hardhat';
import '@nomiclabs/hardhat-waffle';

const printResNumber = (res: any) => {
  return (res as BigNumber).toString();
};

describe('Greeter', function () {
  it('can view', async function () {
    const myContractFactory = await ethers.getContractFactory(
      'CommonPartialERC721'
    );
    const myContract = await myContractFactory.deploy(
      '0x03ab458634910aad20ef5f1c8ee96f1d6ac54919'
    );
    const [owner, addr1, addr2, addr3] = await ethers.getSigners();
    await myContract.deployed();
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0xAE653682Dee958914A82C9628de794dCbbEe3D04'],
    });
    const raiSigner = await ethers.provider.getSigner(
      '0xAE653682Dee958914A82C9628de794dCbbEe3D04'
    );

    // console.log(
    //   printResNumber(await myContract.balanceOf(raiSigner.getAddress()))
    // );

    await myContract.connect(raiSigner).transfer(addr1.address, 1);
    console.log(printResNumber(myContract.connect(addr1).balanceOf(addr1)));
  });
});
