// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";

contract PacoMintTest is TestPacoToken {
    function testSuccessfulMint() public {
        vm.prank(tokenWhale);
        uint256 statedPrice = oneETH * 100;
        uint256 bond = oneETH * 11;
        paco.mint(1, statedPrice, bond);
        assertEq(paco.balanceOf(tokenWhale), 1);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(tokenWhale);
        assertEq(ownedTokens.length, 1);
        uint256 mintedTokenId = ownedTokens[0];
        vm.warp(startBlockTimestamp + 5000);
        uint256 startOnchainBond = paco.getBond(mintedTokenId);
        uint256 feeCollected = SafUtils._calculateSafSinceLastCheckIn(
            statedPrice,
            startBlockTimestamp,
            feeRate
        );
        assertEq(startOnchainBond, bond - feeCollected);
    }

    function testFailMintTooLittleBond() public {
        vm.prank(tokenWhale);
        uint256 statedPrice = oneETH * 100;
        uint256 bond = oneETH * 9;
        paco.mint(1, statedPrice, bond);
    }
}
