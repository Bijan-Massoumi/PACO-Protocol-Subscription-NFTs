// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";

contract PacoAlterSubscriptionPoolTest is TestPacoToken {
    uint256 mintedTokenId;
    uint256 startOnchainSubscriptionPool;
    uint256 startOnchainPrice;

    error InsufficientSubscriptionPool();

    function setUp() public override {
        super.setUp();
        uint256 statedPrice = oneETH * 100;
        uint256 subscriptionPool = oneETH * 11;

        vm.prank(tokenWhale);
        paco.mint(1, statedPrice, subscriptionPool);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(tokenWhale);
        mintedTokenId = ownedTokens[0];
        startOnchainSubscriptionPool = paco.getSubscriptionPool(mintedTokenId);
        startOnchainPrice = paco.getPrice(mintedTokenId);
    }

    function testSubscriptionPoolCanBeIncreased() public {
        uint256 prevBalance = subscriptionPoolToken.balanceOf(tokenWhale);
        vm.prank(tokenWhale);
        paco.increaseSubscriptionPool(mintedTokenId, oneETH * 2);
        uint256 newSubscriptionPool = paco.getSubscriptionPool(mintedTokenId);
        uint256 newBalance = subscriptionPoolToken.balanceOf(tokenWhale);
        assertEq(newSubscriptionPool, startOnchainSubscriptionPool + oneETH * 2);
        assertEq(newBalance, prevBalance - oneETH * 2);
    }

    function testSubscriptionPoolCanBeDecreased() public {
        uint256 beforeBalance = subscriptionPoolToken.balanceOf(tokenWhale);
        vm.prank(tokenWhale);
        paco.decreaseSubscriptionPool(mintedTokenId, oneETH);
        uint256 newSubscriptionPool = paco.getSubscriptionPool(mintedTokenId);
        uint256 afterBalance = subscriptionPoolToken.balanceOf(tokenWhale);
        assertEq(newSubscriptionPool, startOnchainSubscriptionPool - oneETH);
        assertEq(afterBalance, beforeBalance + oneETH);
    }

    function testFailSubscriptionPoolCanNotBeDecreasedBelowZero() public {
        vm.prank(tokenWhale);
        paco.decreaseSubscriptionPool(mintedTokenId, oneETH * 100);
    }

    function testPriceCanBeIncreased() public {
        vm.prank(tokenWhale);
        paco.increaseStatedPrice(mintedTokenId, oneETH * 2);
        uint256 newPrice = paco.getPrice(mintedTokenId);
        assertEq(newPrice, startOnchainPrice + oneETH * 2);
    }

    function testPriceCanBeDecreased() public {
        vm.prank(tokenWhale);
        paco.decreaseStatedPrice(mintedTokenId, oneETH);
        uint256 newPrice = paco.getPrice(mintedTokenId);
        assertEq(newPrice, startOnchainPrice - oneETH);
    }

    function testFailPriceCanNotBeIncreasedBeyondSubscriptionPool() public {
        vm.prank(tokenWhale);
        paco.increaseStatedPrice(mintedTokenId, oneETH * 100);
    }

    function testPriceAndSubscriptionPoolBeIncreased() public {
        vm.prank(tokenWhale);
        paco.alterStatedPriceAndSubscriptionPool(
            mintedTokenId,
            int256(oneETH),
            int256(oneETH * 2)
        );
        uint256 newSubscriptionPool = paco.getSubscriptionPool(mintedTokenId);
        uint256 newPrice = paco.getPrice(mintedTokenId);
        assertEq(newPrice, startOnchainPrice + oneETH);
        assertEq(newSubscriptionPool, startOnchainSubscriptionPool + oneETH * 2);
    }

    function testFailAlterRevertsWithSubscriptionPoolTooLittle() public {
        vm.prank(tokenWhale);
        paco.alterStatedPriceAndSubscriptionPool(
            mintedTokenId,
            int256(oneETH),
            -int256(oneETH * 5)
        );
    }

    function testAlterTokenInLiquidation() public {
        vm.prank(tokenWhale);
        paco.mint(1, oneETH * 100, oneETH * 100);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(tokenWhale);
        uint256 tokenId = ownedTokens[1];
        uint256 fiveYears = startBlockTimestamp + (365 days * 5) + 2 days;
        vm.warp(fiveYears);
        uint256 price = paco.getPrice(tokenId);
        assertEq(price, oneETH * 50);

        vm.expectRevert(InsufficientSubscriptionPool.selector);
        vm.prank(tokenWhale);
        paco.increaseStatedPrice(tokenId, oneETH * 200);

        vm.expectRevert(InsufficientSubscriptionPool.selector);
        vm.prank(tokenWhale);
        paco.increaseSubscriptionPool(tokenId, oneETH * 9);

        vm.prank(tokenWhale);
        paco.increaseSubscriptionPool(tokenId, oneETH * 10);
        price = paco.getPrice(tokenId);
        assertEq(price, oneETH * 100);
    }
}
