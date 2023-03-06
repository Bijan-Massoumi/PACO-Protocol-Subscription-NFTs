// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "../src/PacoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";

contract PacoMintTest is TestPacoToken {
    function testSuccessfulMint() public {
        vm.prank(tokenWhale);
        uint256 statedPrice = oneETH * 100;
        uint256 subscriptionPool = oneETH * 11;
        paco.mint(1, statedPrice, subscriptionPool);
        assertEq(paco.balanceOf(tokenWhale), 1);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(tokenWhale);
        assertEq(ownedTokens.length, 1);
        uint256 mintedTokenId = ownedTokens[0];
        vm.warp(startBlockTimestamp + 5000);
        uint256 startOnchainSubscriptionPool = paco.getSubscriptionPool(
            mintedTokenId
        );
        uint256 feeCollected = SafUtils._calculateSafBetweenTimes(
            statedPrice,
            startBlockTimestamp,
            block.timestamp,
            feeRate
        );
        assertEq(startOnchainSubscriptionPool, subscriptionPool - feeCollected);
    }

    function testFailMintTooLittleSubscriptionPool() public {
        vm.prank(tokenWhale);
        uint256 statedPrice = oneETH * 100;
        uint256 subscriptionPool = oneETH * 9;
        paco.mint(1, statedPrice, subscriptionPool);
    }
}
