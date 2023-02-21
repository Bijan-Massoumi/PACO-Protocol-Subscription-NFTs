// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";

contract PacoFeeTest is TestPacoToken {
    uint256 mintedTokenId;
    uint256 startOnchainBond;
    uint256 startOnchainPrice;
    uint256 secondsInYear = 31536000;
    uint256 secondsInDay = 86400;

    function setUp() public override {
        super.setUp();
        uint256 statedPrice = oneETH * 100;
        uint256 bond = oneETH * 100;

        vm.prank(tokenWhale);
        paco.mint(1, statedPrice, bond);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(tokenWhale);
        mintedTokenId = ownedTokens[0];
        startOnchainBond = paco.getBond(mintedTokenId);
        startOnchainPrice = paco.getPrice(mintedTokenId);
    }

    function testFeeCalculationAfterMint() public {
        vm.warp(startBlockTimestamp + secondsInYear);
        uint256 feeCollected = SafUtils._calculateSafSinceLastCheckIn(
            startOnchainPrice,
            startBlockTimestamp,
            feeRate
        );
        assertEq(feeCollected, oneETH * 20);
    }

    function testBondCalculatedCorrectlyAfterPriceIncrease() public {
        vm.warp(startBlockTimestamp + secondsInYear);
        uint256 remainingBond = paco.getBond(mintedTokenId);
        assertEq(remainingBond, oneETH * 80);

        vm.prank(tokenWhale);
        paco.increaseStatedPrice(mintedTokenId, oneETH * 100);
        vm.warp(startBlockTimestamp + secondsInYear * 2);
        remainingBond = paco.getBond(mintedTokenId);
        assertEq(remainingBond, oneETH * 40);
    }

    function testBondRemainingNeverNegative() public {
        vm.warp(startBlockTimestamp + secondsInYear * 10);
        uint256 remainingBond = paco.getBond(mintedTokenId);
        assertEq(remainingBond, 0);
    }

    function testReapSafForCreator() public {
        uint256 ownerStartBond = oneETH * 5;
        vm.prank(owner);
        paco.mint(1, oneETH * 10, ownerStartBond);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(owner);
        uint256 newToken = ownedTokens[0];

        vm.warp(startBlockTimestamp + secondsInYear);
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = mintedTokenId;
        tokens[1] = newToken;

        paco.reapAndWithdrawFees(tokens);
        uint256 balance = tokenContract.balanceOf(withdrawAddr);
        assertEq(balance, oneETH * 20 + oneETH * 2);
    }
}
