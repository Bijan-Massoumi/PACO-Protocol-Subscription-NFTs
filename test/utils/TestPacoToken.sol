// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./TestERC20.sol";

abstract contract TestPacoToken is Test {
    PaCoExample paco;
    TestToken tokenContract;
    uint256 oneETH = 10**18;

    address withdrawAddr = address(1137);
    address tokenWhale = 0xBecAa4aD36e5d134fD6979cc6780EB48aC5B5a93;
    address owner = address(1);
    address addr2 = address(2);
    address addr3 = address(3);
    uint256 startBlockTimestamp = 1642941822;
    uint16 feeRate = 2000;

    function setUp() public virtual {
        vm.warp(startBlockTimestamp);
        tokenContract = new TestToken("TestToken", "TT");
        vm.prank(tokenWhale);
        tokenContract.mint(oneETH * 1000000000);
        vm.startPrank(owner);
        paco = new PaCoExample(address(tokenContract), withdrawAddr, feeRate);
        paco.setSaleStatus(true);
        vm.stopPrank();

        vm.prank(tokenWhale);
        tokenContract.approve(address(paco), oneETH * 10000);
        vm.prank(owner);
        tokenContract.approve(address(paco), oneETH * 10000);
        vm.prank(addr2);
        tokenContract.approve(address(paco), oneETH * 10000);

        vm.startPrank(tokenWhale);
        tokenContract.transfer(owner, oneETH * 500);
        tokenContract.transfer(addr2, oneETH * 500);
        vm.stopPrank();
    }
}
