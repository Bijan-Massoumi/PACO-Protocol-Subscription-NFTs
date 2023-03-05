// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../../src/PaCoSeaportExample.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./TestERC20.sol";
import {OfferItem, ConsiderationItem} from "../../src/SeaportStructs.sol";

struct OwnerBalance {
    uint256 ownerBalance;
    address owner;
}

abstract contract TestSeaportPacoToken is Test {
    PaCoSeaportExample paco;
    TestToken bondToken;
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
        bondToken = new TestToken("TestToken", "TT");
        vm.prank(tokenWhale);
        bondToken.mint(oneETH * 1000000000);
        vm.startPrank(owner);
        paco = new PaCoSeaportExample(
            address(bondToken),
            withdrawAddr,
            feeRate,
            seaportAddress
        );
        vm.stopPrank();

        // approve PaCo allowance for bond token
        vm.prank(tokenWhale);
        bondToken.approve(address(paco), oneETH * 10000);
        vm.prank(owner);
        bondToken.approve(address(paco), oneETH * 10000);
        vm.prank(addr2);
        bondToken.approve(address(paco), oneETH * 10000);
        vm.prank(addr3);
        bondToken.approve(address(paco), oneETH * 10000);

        // fund wallets
        vm.startPrank(tokenWhale);
        bondToken.transfer(owner, oneETH * 500);
        bondToken.transfer(addr2, oneETH * 500);
        bondToken.transfer(addr3, oneETH * 500);
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
        bondToken.approve(address(paco), oneETH * 10000);
        bondToken.approve(seaportAddress, oneETH * 10000);
        vm.stopPrank();
    }

    function approveSeaportPaco(address addr, uint256 tokenId) public {
        vm.prank(addr);
        paco.approve(seaportAddress, tokenId);
    }

    function createOfferForTokenIds(uint256[] memory tokenIds)
        public
        view
        returns (OfferItem[] memory)
    {
        OfferItem[] memory offer = new OfferItem[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            offer[i] = OfferItem(
                ItemType.ERC721,
                address(paco),
                tokenIds[i],
                1,
                1
            );
        }
        return offer;
    }

    function createConsiderationForTokenIds(uint256[] memory tokenIds)
        public
        view
        returns (ConsiderationItem[] memory, uint256)
    {
        ConsiderationItem[] memory consideration = new ConsiderationItem[](
            tokenIds.length
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 price = paco.getPrice(tokenIds[i]);
            consideration[i] = ConsiderationItem(
                ItemType.ERC20,
                address(bondToken),
                0,
                price,
                price,
                payable(paco.ownerOf(tokenIds[i]))
            );
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
            uint256 ownerBalance = bondToken.balanceOf(owner);
            ownerBal[i] = OwnerBalance(ownerBalance, tokenOwner);
        }
        return ownerBal;
    }
}
