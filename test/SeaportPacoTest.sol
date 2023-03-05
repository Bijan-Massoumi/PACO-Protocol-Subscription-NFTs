// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestSeaportPacoToken.sol";
import {OfferItem, ConsiderationItem} from "../src/SeaportStructs.sol";

contract SeaportPacoTest is TestSeaportPacoToken {
    uint256 whaleTokenId;
    uint256 ownerTokenId;

    function setUp() public override {
        super.setUp();
        uint256 statedPrice = oneETH * 100;
        uint256 bond = oneETH * 100;

        vm.prank(tokenWhale);
        paco.mint(1, statedPrice, bond);
        uint256[] memory whaleTokens = paco.getTokenIdsForAddress(tokenWhale);
        whaleTokenId = whaleTokens[0];

        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(owner);
        ownerTokenId = ownedTokens[0];
    }

    function testBasicSeaportTx() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = whaleTokenId;
        OfferItem[] memory offer = createOfferForTokenIds(tokenIds);

        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(tokenIds);

        uint256 newPrice = oneETH * 10;
        uint256[] memory prices = new uint256[](1);
        prices[0] = newPrice;

        uint256 cost = consideration[0].endAmount;
        uint256 beforeBalance = bondToken.balanceOf(tokenWhale);

        uint256 minBond = 1000;
        uint256 newBond = ((newPrice * minBond) / 10000) + 1;
        uint256[] memory bonds = new uint256[](1);
        bonds[0] = newBond;
        vm.prank(owner);
        paco.fulfillOrder(offer, consideration, prices, bonds);

        assertEq(paco.ownerOf(whaleTokenId), owner);
        assertEq(bondToken.balanceOf(tokenWhale), beforeBalance + cost);
        assertEq(paco.getPrice(whaleTokenId), newPrice);
    }

    function testMultipleSeaportTx() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 4;
        tokenIds[2] = 7;
        OfferItem[] memory offer = createOfferForTokenIds(tokenIds);
        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(tokenIds);

        uint256 newPrice1 = oneETH * 10;
        uint256 newPrice2 = oneETH * 15;
        uint256 newPrice3 = oneETH * 20;
        uint256[] memory prices = new uint256[](3);
        prices[0] = newPrice1;
        prices[1] = newPrice2;
        prices[2] = newPrice3;

        uint256[] memory bonds = new uint256[](3);
        for (uint256 i = 0; i < prices.length; i++) {
            uint256 newPrice = prices[i];
            uint256 minBond = 1000;
            bonds[i] = ((newPrice * minBond) / 10000) + 1;
        }

        OwnerBalance[] memory prevBalances = getOwnerWithPrevBalances(tokenIds);
        vm.prank(tokenWhale);
        paco.fulfillOrder(offer, consideration, prices, bonds);

        assertEq(paco.ownerOf(0), tokenWhale);
        assertEq(paco.ownerOf(4), tokenWhale);
        assertEq(paco.ownerOf(7), tokenWhale);
        OwnerBalance[] memory newBalances = getOwnerWithPrevBalances(tokenIds);
        for (uint256 i = 0; i < prevBalances.length; i++) {
            OwnerBalance memory prevBalance = prevBalances[i];
            OwnerBalance memory newBalance = newBalances[i];
            assertEq(
                newBalance.ownerBalance,
                prevBalance.ownerBalance + consideration[i].endAmount
            );
        }
    }
}
