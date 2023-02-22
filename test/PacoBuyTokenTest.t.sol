// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";

contract PacoBuyTokenTest is TestPacoToken {
    uint256 whaleTokenId;
    uint256 ownerTokenId;
    uint256 startOnchainBond;
    uint256 startOnchainPrice;
    address emptyAddress;

    error InsufficientBond();

    function setUp() public override {
        super.setUp();
        uint256 statedPrice = oneETH * 100;
        uint256 bond = oneETH * 100;

        vm.prank(tokenWhale);
        paco.mint(1, statedPrice, bond);
        uint256[] memory whaleTokens = paco.getTokenIdsForAddress(tokenWhale);
        whaleTokenId = whaleTokens[0];

        vm.prank(owner);
        paco.mint(1, oneETH * 10, oneETH * 5);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(owner);
        ownerTokenId = ownedTokens[0];

        emptyAddress = address(0x1234);
        approveNewAddress(emptyAddress);
    }

    function testCanBuyTokenPullBondRefund() public {
        vm.warp(startBlockTimestamp + 365 days);
        uint256 price = paco.getPrice(whaleTokenId);
        uint256 whalesPrevBalance = bondToken.balanceOf(tokenWhale);

        vm.prank(owner);
        paco.buyToken(whaleTokenId, price + oneETH, price / 2);

        assertEq(paco.ownerOf(whaleTokenId), owner);
        assertEq(
            bondToken.balanceOf(tokenWhale),
            whalesPrevBalance + price + oneETH * 80
        );
    }

    function testFailCannotBuyTokenIfBondTooLow() public {
        uint256 price = paco.getPrice(whaleTokenId);
        vm.prank(owner);
        paco.buyToken(whaleTokenId, price + oneETH, 1);
    }

    function testFailCannotBuyTokenWithInsufficientFunds() public {
        uint256 price = paco.getPrice(whaleTokenId);
        vm.prank(emptyAddress);
        paco.buyToken(whaleTokenId, price - oneETH, price / 2);
    }

    function testCannotBuyTokenIfNotEnoughFundsForBond() public {
        uint256 price = paco.getPrice(whaleTokenId);
        vm.prank(tokenWhale);
        bondToken.transfer(emptyAddress, price + oneETH);
        vm.expectRevert(InsufficientBond.selector);
        vm.prank(emptyAddress);
        paco.buyToken(whaleTokenId, price + 1, oneETH / 2);
    }

    function testBuyLiquidatingToken() public {
        uint256 fiveYears = startBlockTimestamp + (365 days * 5) + 2 days;
        vm.warp(fiveYears);
        uint256 price = paco.getPrice(whaleTokenId);
        assertEq(price, oneETH * 50);

        uint256 balanceBefore = bondToken.balanceOf(tokenWhale);
        vm.prank(owner);
        paco.buyToken(whaleTokenId, oneETH * 50, oneETH * 10);
        assertEq(paco.ownerOf(whaleTokenId), owner);
        assertEq(bondToken.balanceOf(tokenWhale), balanceBefore + oneETH * 50);
    }
}
