// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./TestERC20.sol";
import {AdvancedOrder, OrderParameters} from "../../src/SeaportStructs.sol";

abstract contract TestPacoToken is Test {
    PaCoExample paco;
    TestToken subscriptionPoolToken;
    uint256 oneETH = 10**18;

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
        paco = new PaCoExample(
            address(subscriptionPoolToken),
            withdrawAddr,
            feeRate
        );
        vm.stopPrank();

        // approve PaCo allowance for subscriptionPool token
        vm.prank(tokenWhale);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.prank(owner);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.prank(addr2);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);

        // fund wallets
        vm.startPrank(tokenWhale);
        subscriptionPoolToken.transfer(owner, oneETH * 500);
        subscriptionPoolToken.transfer(addr2, oneETH * 500);
        vm.stopPrank();
    }

    function approveNewAddress(address addr) public {
        vm.startPrank(addr);
        subscriptionPoolToken.approve(address(paco), oneETH * 10000);
        vm.stopPrank();
    }
}
