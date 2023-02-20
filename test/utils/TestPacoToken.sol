// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract TestPacoToken is Test {
    PaCoExample paco;
    IERC20 tokenContract = IERC20(wethAddr);
    uint256 oneETH = 10**18;

    address wethAddr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address withdrawAddr = address(1137);
    address wethWhale = 0xBecAa4aD36e5d134fD6979cc6780EB48aC5B5a93;
    address owner = address(1);
    address addr2 = address(2);
    address addr3 = address(3);
    uint256 startBlockTimestamp = 1642941822;
    uint16 feeRate = 2000;

    function setUp() public virtual {
        vm.warp(startBlockTimestamp);
        vm.prank(owner);
        paco = new PaCoExample(wethAddr, withdrawAddr, feeRate);
        vm.prank(owner);
        paco.setSaleStatus(true);

        console.log("here");
        vm.prank(wethWhale);
        tokenContract.approve(address(paco), oneETH * 10000);
        console.log("there1");
        vm.prank(owner);
        tokenContract.approve(address(paco), oneETH * 10000);
        console.log("there2");
        vm.prank(addr2);
        tokenContract.approve(address(paco), oneETH * 10000);
        console.log("there3");
        vm.prank(wethWhale);
        tokenContract.transfer(owner, oneETH * 500);
        console.log("there4");
        vm.prank(wethWhale);
        tokenContract.transfer(addr2, oneETH * 500);
    }
}
