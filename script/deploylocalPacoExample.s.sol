// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../test/utils/TestPacoToken.sol";
import "forge-std/Script.sol";
import "../test/utils/TestSeaportPacoToken.sol";

contract DeployLocal is Script {
    TestToken subscriptionPoolToken;
    PacoExample paco;
    uint256 oneETH = 10 ** 18;
    address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address pub1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address pub2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address pub3 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    uint256 feeRate = 2000;

    function run() public {
        uint256 ownerpk = vm.envUint("PRIVATE_KEY");
        uint256 acct1 = vm.envUint("PRIVATE_KEY1");
        uint256 acct2 = vm.envUint("PRIVATE_KEY2");
        uint256 acct3 = vm.envUint("PRIVATE_KEY3");

        vm.startBroadcast(ownerpk);
        subscriptionPoolToken = new TestToken("TestToken", "TT");

        subscriptionPoolToken.mint(oneETH * 1000000000);
        subscriptionPoolToken.transfer(pub1, oneETH * 500);
        subscriptionPoolToken.transfer(pub2, oneETH * 500);
        subscriptionPoolToken.transfer(pub3, oneETH * 500);
        paco = new PacoExample(address(subscriptionPoolToken), owner, feeRate);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);

        uint256 statedPrice = oneETH * 100;
        uint256 subscriptionPool = oneETH * 100;
        paco.mint(2, statedPrice, subscriptionPool);
        uint256[] memory tokenIds = paco.getTokenIdsForAddress(owner);
        uint256 tokenOne = tokenIds[0];
        uint256 tokenTwo = tokenIds[1];

        paco.increaseStatedPrice(tokenOne, oneETH);
        paco.decreaseSubscriptionPool(tokenOne, 5 * oneETH);

        paco.alterStatedPriceAndSubscriptionPool(
            tokenTwo,
            int256(5 * oneETH),
            -5 * int256(oneETH)
        );

        vm.stopBroadcast();

        vm.startBroadcast(acct1);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        paco.buyToken(tokenOne, 100 * oneETH, 20 * oneETH);
        paco.increaseSubscriptionPool(tokenOne, oneETH);
        vm.stopBroadcast();

        vm.startBroadcast(acct2);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.stopBroadcast();

        vm.startBroadcast(acct3);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.stopBroadcast();
    }
}
