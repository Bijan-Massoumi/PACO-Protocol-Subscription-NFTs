import { BigNumber, Contract } from 'ethers';
import { JsonRpcSigner } from '@ethersproject/providers';
import { network } from 'hardhat';
import '@nomiclabs/hardhat-waffle';

export const increaseTime = async (amount: number) => {
  await network.provider.send('evm_increaseTime', [amount]);
  await network.provider.send('evm_mine');
};
