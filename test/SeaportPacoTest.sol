// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";
import {OfferItem, ConsiderationItem} from "../src/SeaportStructs.sol";

contract SeaportPacoTest is TestPacoToken {
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

        vm.startPrank(owner);
        paco.mint(1, oneETH * 10, oneETH * 5);
        bondToken.approve(seaportAddress, oneETH * 10000);
        vm.stopPrank();
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(owner);
        ownerTokenId = ownedTokens[0];
    }

    function testSeaportTx() public {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem(
            ItemType.ERC721,
            address(paco),
            whaleTokenId,
            1,
            1
        );

        uint256 price = paco.getPrice(whaleTokenId);
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem(
            ItemType.ERC20,
            address(bondToken),
            0,
            price,
            price,
            payable(paco.ownerOf(whaleTokenId))
        );

        uint256[] memory prices = new uint256[](1);
        prices[0] = price;

        uint256 minBond = 1000;
        uint256 newBond = ((price * minBond) / 10000) + 1;
        uint256[] memory bonds = new uint256[](1);
        bonds[0] = newBond;

        console.log("before", tokenWhale);
        vm.prank(owner);
        paco.fulfillOrder(offer, consideration, prices, bonds);
    }
}
