// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestSeaportPacoToken.sol";
import {OfferItem, ConsiderationItem} from "../src/SeaportStructs.sol";
import {ISeaportErrors} from "../src/ISeaportErrors.sol";

contract SeaportPacoTest is TestSeaportPacoToken, ISeaportErrors {
    uint256 whaleTokenId;
    uint256 ownerTokenId;
    uint256 minBond = 1000;
    uint256[] multiPrices;
    uint256[] multiBonds;
    uint256 prevContractBalance;

    ConsiderationItem emptyItem =
        ConsiderationItem(
            ItemType.ERC20,
            address(0),
            0,
            0,
            0,
            payable(address(0))
        );

    OfferItem emptyOfferItem = OfferItem(ItemType.ERC721, address(0), 0, 1, 1);

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

        uint256 newPrice1 = oneETH * 10;
        uint256 newPrice2 = oneETH * 15;
        uint256 newPrice3 = oneETH * 20;

        multiPrices.push(newPrice1);
        multiPrices.push(newPrice2);
        multiPrices.push(newPrice3);

        for (uint256 i = 0; i < multiPrices.length; i++) {
            uint256 newPrice = multiPrices[i];
            multiBonds.push(((newPrice * minBond) / 10000) + 1);
        }
        prevContractBalance = bondToken.balanceOf(address(paco));
    }

    function testBasicSeaportTx() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = whaleTokenId;
        OfferItem[] memory offer = createOfferForTokenIds(
            tokenIds,
            emptyOfferItem
        );

        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(
            tokenIds,
            emptyItem
        );

        uint256 newPrice = oneETH * 10;
        uint256[] memory prices = new uint256[](1);
        prices[0] = newPrice;

        uint256 cost = consideration[0].endAmount;
        uint256 beforeBalance = bondToken.balanceOf(tokenWhale);
        uint256 remainingBond = paco.getBond(whaleTokenId);

        uint256 newBond = ((newPrice * minBond) / 10000) + 1;
        uint256[] memory bonds = new uint256[](1);
        bonds[0] = newBond;
        vm.prank(owner);
        paco.fulfillOrder(offer, consideration, prices, bonds);

        assertEq(paco.ownerOf(whaleTokenId), owner);
        assertEq(
            bondToken.balanceOf(tokenWhale),
            beforeBalance + cost + remainingBond
        );
        assertEq(paco.getPrice(whaleTokenId), newPrice);
        assertEq(
            bondToken.balanceOf(address(paco)),
            prevContractBalance + newBond - remainingBond
        );
    }

    function testMultipleSeaportTx() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 4;
        tokenIds[2] = 7;
        OfferItem[] memory offer = createOfferForTokenIds(
            tokenIds,
            emptyOfferItem
        );
        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(
            tokenIds,
            emptyItem
        );

        OwnerBalance[] memory prevBalances = getOwnerWithPrevBalances(tokenIds);
        vm.prank(tokenWhale);
        paco.fulfillOrder(offer, consideration, multiPrices, multiBonds);
        assertEq(paco.ownerOf(0), tokenWhale);
        assertEq(paco.ownerOf(4), tokenWhale);
        assertEq(paco.ownerOf(7), tokenWhale);

        uint256 totalRefund = 0;
        uint256 totalNewBond = 0;
        for (uint256 i = 0; i < multiBonds.length; i++) {
            totalNewBond += multiBonds[i];
        }
        OwnerBalance[] memory newBalances = getOwnerWithPrevBalances(tokenIds);
        for (uint256 i = 0; i < prevBalances.length; i++) {
            OwnerBalance memory prevBalance = prevBalances[i];
            OwnerBalance memory newBalance = newBalances[i];
            totalRefund += prevBalance.ownerBondRemaining;
            assertEq(
                newBalance.ownerBalance,
                prevBalance.ownerBalance +
                    consideration[i].endAmount +
                    prevBalance.ownerBondRemaining
            );
        }

        assertEq(
            bondToken.balanceOf(address(paco)),
            prevContractBalance + totalNewBond - totalRefund
        );
    }

    function testMultipleTokensWithExtraConsideration() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 4;
        tokenIds[2] = 7;
        OfferItem[] memory offer = createOfferForTokenIds(
            tokenIds,
            emptyOfferItem
        );
        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(
            tokenIds,
            emptyItem
        );

        consideration[0].endAmount /= 2;
        consideration[0].startAmount /= 2;
        consideration[1].endAmount /= 2;
        consideration[1].startAmount /= 2;
        ConsiderationItem[] memory extraConsideration = new ConsiderationItem[](
            2
        );
        extraConsideration[0] = consideration[0];
        extraConsideration[1] = consideration[1];
        consideration = combineConsiderations(
            consideration,
            extraConsideration
        );

        OwnerBalance[] memory prevBalances = getOwnerWithPrevBalances(tokenIds);
        vm.prank(tokenWhale);
        paco.fulfillOrder(offer, consideration, multiPrices, multiBonds);

        assertEq(paco.ownerOf(0), tokenWhale);
        assertEq(paco.ownerOf(4), tokenWhale);
        assertEq(paco.ownerOf(7), tokenWhale);

        uint256 totalRefund = 0;
        uint256 totalNewBond = 0;
        for (uint256 i = 0; i < multiBonds.length; i++) {
            totalNewBond += multiBonds[i];
        }
        OwnerBalance[] memory newBalances = getOwnerWithPrevBalances(tokenIds);
        for (uint256 i = 0; i < prevBalances.length; i++) {
            OwnerBalance memory prevBalance = prevBalances[i];
            OwnerBalance memory newBalance = newBalances[i];
            totalRefund += prevBalance.ownerBondRemaining;
            assertEq(
                newBalance.ownerBalance,
                prevBalance.ownerBalance +
                    paco.getPrice(consideration[i].identifierOrCriteria) +
                    prevBalance.ownerBondRemaining
            );
        }

        assertEq(
            bondToken.balanceOf(address(paco)),
            prevContractBalance + totalNewBond - totalRefund
        );
    }

    function testRevertNonValidToken() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 4;
        tokenIds[2] = 7;

        OfferItem[] memory offer = createOfferForTokenIds(
            tokenIds,
            OfferItem(ItemType.ERC721, address(23847), 5, 1, 1)
        );
        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(
            tokenIds,
            emptyItem
        );

        vm.prank(tokenWhale);
        vm.expectRevert(NonPacoToken.selector);
        paco.fulfillOrder(offer, consideration, multiPrices, multiBonds);

        offer = createOfferForTokenIds(tokenIds, emptyOfferItem);
        (consideration, size) = createConsiderationForTokenIds(
            tokenIds,
            ConsiderationItem(
                ItemType.ERC20,
                address(12345),
                0,
                oneETH,
                oneETH,
                payable(address(12345))
            )
        );

        vm.prank(tokenWhale);
        vm.expectRevert(NonBondToken.selector);
        paco.fulfillOrder(offer, consideration, multiPrices, multiBonds);
    }

    function testRevertInsufficientOwnerPayment() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 4;
        tokenIds[2] = 7;

        OfferItem[] memory offer = createOfferForTokenIds(
            tokenIds,
            emptyOfferItem
        );

        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(
            tokenIds,
            emptyItem
        );
        consideration[0].endAmount -= oneETH;
        consideration[0].startAmount -= oneETH;
        consideration[2].endAmount -= oneETH;
        consideration[2].startAmount -= oneETH;

        vm.prank(tokenWhale);
        vm.expectRevert(InsufficientOwnerPayment.selector);
        paco.fulfillOrder(offer, consideration, multiPrices, multiBonds);
    }
}
