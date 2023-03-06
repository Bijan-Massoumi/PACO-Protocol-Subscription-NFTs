// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../../src/PaCoSeaportExample.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./TestERC20.sol";
import {OfferItem, ConsiderationItem} from "../../src/SeaportStructs.sol";

struct OwnerBalance {
    uint256 ownerBalance;
    uint256 ownerSubscriptionPoolRemaining;
    address owner;
}

abstract contract TestSeaportPacoToken is Test {
    PaCoSeaportExample paco;
    TestToken subscriptionPoolToken;
    uint256 oneETH = 10**18;

    address seaportAddress = 0x00000000006c3852cbEf3e08E8dF289169EdE581;

    address withdrawAddr = address(1137);
    address tokenWhale = 0xBecAa4aD36e5d134fD6979cc6780EB48aC5B5a93;
    address owner = address(1);
    address addr2 = address(2);
    address addr3 = address(3);

    uint256 startBlockTimestamp = 1642941822;
    // 20% annual rate
    uint16 feeRate = 2000;

    function setUp() public virtual {
        // launch contracts
        vm.warp(startBlockTimestamp);
        subscriptionPoolToken = new TestToken("TestToken", "TT");
        vm.prank(tokenWhale);
        subscriptionPoolToken.mint(oneETH * 1000000000);
        vm.startPrank(owner);
        paco = new PaCoSeaportExample(
            address(subscriptionPoolToken),
            withdrawAddr,
            feeRate,
            seaportAddress
        );
        vm.stopPrank();

        // approve PaCo allowance for subscriptionPool token
        vm.prank(tokenWhale);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.prank(owner);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.prank(addr2);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.prank(addr3);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);

        // fund wallets
        vm.startPrank(tokenWhale);
        subscriptionPoolToken.transfer(owner, oneETH * 500);
        subscriptionPoolToken.transfer(addr2, oneETH * 500);
        subscriptionPoolToken.transfer(addr3, oneETH * 500);
        vm.stopPrank();

        // mint multiple paco tokens to each wallet
        // 0x01: tokenIds 0, 1, 2
        // 0x02: tokenIds 3, 4, 5
        // 0x03: tokenIds 6, 7, 8
        vm.prank(owner);
        paco.mint(3, oneETH * 10, oneETH * 4);
        vm.prank(addr2);
        paco.mint(3, oneETH * 10, oneETH * 4);
        vm.prank(addr3);
        paco.mint(3, oneETH * 10, oneETH * 4);
    }

    function approveNewAddress(address addr) public {
        vm.startPrank(addr);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        subscriptionPoolToken.approve(seaportAddress, oneETH * 10000);
        vm.stopPrank();
    }

    function approveSeaportPaco(address addr, uint256 tokenId) public {
        vm.prank(addr);
        paco.approve(seaportAddress, tokenId);
    }

    function createOfferForTokenIds(
        uint256[] memory tokenIds,
        OfferItem memory extraOffer
    ) public view returns (OfferItem[] memory) {
        uint256 size;
        if (extraOffer.token == address(0)) {
            size = tokenIds.length;
        } else {
            size = tokenIds.length + 1;
        }

        OfferItem[] memory offer = new OfferItem[](size);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            offer[i] = OfferItem(
                ItemType.ERC721,
                address(paco),
                tokenIds[i],
                1,
                1
            );
        }

        if (size > tokenIds.length) {
            offer[size - 1] = extraOffer;
        }
        return offer;
    }

    function createConsiderationForTokenIds(
        uint256[] memory tokenIds,
        ConsiderationItem memory extraConsideration
    ) public view returns (ConsiderationItem[] memory, uint256) {
        uint256 size;
        if (extraConsideration.token == address(0)) {
            size = tokenIds.length;
        } else {
            size = tokenIds.length + 1;
        }

        ConsiderationItem[] memory consideration = new ConsiderationItem[](
            size
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 price = paco.getPrice(tokenIds[i]);
            consideration[i] = ConsiderationItem(
                ItemType.ERC20,
                address(subscriptionPoolToken),
                0,
                price,
                price,
                payable(paco.ownerOf(tokenIds[i]))
            );
        }
        if (size > tokenIds.length) {
            consideration[size - 1] = extraConsideration;
        }

        return (consideration, consideration.length);
    }

    function getOwnerWithPrevBalances(uint256[] memory tokenIds)
        public
        view
        returns (OwnerBalance[] memory)
    {
        OwnerBalance[] memory ownerBal = new OwnerBalance[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            address tokenOwner = paco.ownerOf(tokenIds[i]);
            uint256 subscriptionPool = paco.getSubscriptionPool(tokenIds[i]);
            uint256 ownerBalance = subscriptionPoolToken.balanceOf(owner);
            ownerBal[i] = OwnerBalance(
                ownerBalance,
                subscriptionPool,
                tokenOwner
            );
        }
        return ownerBal;
    }

    function combineConsiderations(
        ConsiderationItem[] memory consideration,
        ConsiderationItem[] memory extraConsideration
    ) public pure returns (ConsiderationItem[] memory) {
        ConsiderationItem[] memory result = new ConsiderationItem[](
            consideration.length + extraConsideration.length
        );
        uint256 index = 0;

        for (uint256 i = 0; i < consideration.length; i++) {
            result[index] = consideration[i];
            index++;
        }

        for (uint256 i = 0; i < extraConsideration.length; i++) {
            result[index] = extraConsideration[i];
            index++;
        }

        return result;
    }
}
