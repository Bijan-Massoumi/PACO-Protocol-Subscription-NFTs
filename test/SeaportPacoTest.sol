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

    function testSeaportTx() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = whaleTokenId;
        OfferItem[] memory offer = createOfferForTokenIds(tokenIds);

        uint256 size;
        ConsiderationItem[] memory consideration;
        (consideration, size) = createConsiderationForTokenIds(tokenIds);

        uint256 newPrice = oneETH * 10;
        uint256[] memory prices = new uint256[](1);
        prices[0] = newPrice;

        uint256 minBond = 1000;
        uint256 newBond = ((newPrice * minBond) / 10000) + 1;
        uint256[] memory bonds = new uint256[](1);
        bonds[0] = newBond;

        vm.prank(owner);
        paco.fulfillOrder(offer, consideration, prices, bonds);
    }
}
