// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";

contract PacoFeeTest is TestPacoToken {
    uint256 mintedTokenId;
    uint256 ownerTokenId;
    uint256 startOnchainPrice;

    function setUp() public override {
        super.setUp();
        uint256 statedPrice = oneETH * 100;
        uint256 subscriptionPool = oneETH * 100;

        vm.prank(tokenWhale);
        paco.mint(1, statedPrice, subscriptionPool);
        uint256[] memory whaleTokens = paco.getTokenIdsForAddress(tokenWhale);
        mintedTokenId = whaleTokens[0];
        startOnchainPrice = paco.getPrice(mintedTokenId);

        vm.prank(owner);
        paco.mint(1, oneETH * 10, oneETH * 5);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(owner);
        ownerTokenId = ownedTokens[0];
    }

    function testFeeCalculationAfterMint() public {
        vm.warp(startBlockTimestamp + 365 days);
        uint256 feeCollected = SafUtils._calculateSafBetweenTimes(
            startOnchainPrice,
            startBlockTimestamp,
            block.timestamp,
            feeRate
        );
        assertEq(feeCollected, oneETH * 20);
    }

    function testSubscriptionPoolCalculatedCorrectlyAfterPriceIncrease()
        public
    {
        vm.warp(startBlockTimestamp + 365 days);
        uint256 remainingSubscriptionPool = paco.getSubscriptionPoolRemaining(
            mintedTokenId
        );
        assertEq(remainingSubscriptionPool, oneETH * 80);

        vm.prank(tokenWhale);
        paco.increaseStatedPrice(mintedTokenId, oneETH * 100);
        vm.warp(startBlockTimestamp + 365 days * 2);
        remainingSubscriptionPool = paco.getSubscriptionPoolRemaining(
            mintedTokenId
        );
        assertEq(remainingSubscriptionPool, oneETH * 40);
    }

    function testSubscriptionPoolRemainingNeverNegative() public {
        vm.warp(startBlockTimestamp + 365 days * 10);
        uint256 remainingSubscriptionPool = paco.getSubscriptionPoolRemaining(
            mintedTokenId
        );
        assertEq(remainingSubscriptionPool, 0);
    }

    function testReapSafForCreator() public {
        vm.warp(startBlockTimestamp + 365 days);
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = mintedTokenId;
        tokens[1] = ownerTokenId;

        uint256 expectedAnnualFees = oneETH * 20 + oneETH * 2;
        paco.reapAndWithdrawFees(tokens);
        uint256 balance = subscriptionPoolToken.balanceOf(withdrawAddr);
        assertEq(balance, expectedAnnualFees);

        vm.warp(startBlockTimestamp + 365 days * 2);
        paco.reapAndWithdrawFees(tokens);
        balance = subscriptionPoolToken.balanceOf(withdrawAddr);
        assertEq(balance, expectedAnnualFees * 2);
    }

    function testWithdrawFeesAfterOwnerAlters() public {
        vm.warp(startBlockTimestamp + 365 days);
        vm.prank(tokenWhale);
        paco.alterStatedPriceAndSubscriptionPool(mintedTokenId, 1, 1);
        vm.prank(owner);
        paco.alterStatedPriceAndSubscriptionPool(ownerTokenId, 1, 1);
        paco.withdrawAccumulatedFees();
        uint256 balance = subscriptionPoolToken.balanceOf(withdrawAddr);
        assertEq(balance, oneETH * 20 + oneETH * 2);
    }

    function testFeeIsComputedCorrectlyInLiquidation() public {
        uint256 fiveYears = startBlockTimestamp + 365 days * 5;
        vm.warp(fiveYears);
        uint256 remainingSubscriptionPool = paco.getSubscriptionPoolRemaining(
            mintedTokenId
        );
        assertEq(remainingSubscriptionPool, 0);
        bool isLiquidating = paco.isBeingLiquidated(mintedTokenId);
        assertEq(isLiquidating, false);

        uint256 prevPrice = paco.getPrice(mintedTokenId);
        vm.warp(fiveYears + 2 days);
        uint256 price = paco.getPrice(mintedTokenId);
        assertEq(price, prevPrice / 2);
        vm.warp(fiveYears + 4 days);
        price = paco.getPrice(mintedTokenId);
        assertEq(price, prevPrice / 4);
    }

    function testFeeComputedCorrectlyAfterFeeChanges() public {
        vm.startPrank(owner);
        vm.warp(startBlockTimestamp + 365 days);
        paco.setSubscriptionRate(1000);
        vm.warp(startBlockTimestamp + 365 days * 2);
        paco.setSubscriptionRate(500);
        vm.warp(startBlockTimestamp + 365 days * 3);
        vm.stopPrank();
        uint256 subscriptionPool = paco.getSubscriptionPoolRemaining(
            mintedTokenId
        );
        assertEq(subscriptionPool, oneETH * 65);
    }

    function testLiquidationTimeCalculationAfterFeeChange() public {
        vm.startPrank(owner);
        vm.warp(startBlockTimestamp + 365 days * 3);
        paco.setSubscriptionRate(1000);
        vm.warp(startBlockTimestamp + 365 days * 7);
        vm.stopPrank();
        uint256 subscriptionPool = paco.getSubscriptionPoolRemaining(
            mintedTokenId
        );
        bool isLiquidating = paco.isBeingLiquidated(mintedTokenId);
        assertEq(subscriptionPool, 0);
        assertEq(isLiquidating, false);

        vm.warp(startBlockTimestamp + (365 days * 7) + 2 days);
        uint256 price = paco.getPrice(mintedTokenId);
        assertEq(price, oneETH * 50);
    }
}
