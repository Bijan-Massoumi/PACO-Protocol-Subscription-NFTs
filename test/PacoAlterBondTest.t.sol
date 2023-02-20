// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "../src/PaCoExample.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";
import "../src/SafUtils.sol";
import "./utils/TestPacoToken.sol";

contract PacoAlterBondTest is TestPacoToken {
    uint256 mintedTokenId;
    uint256 onchainBond;
    uint256 onchainPrice;

    function setUp() public override {
        super.setUp();
        uint256 statedPrice = oneETH * 100;
        uint256 bond = oneETH * 11;

        vm.prank(tokenWhale);
        paco.mint(1, statedPrice, bond);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(tokenWhale);
        mintedTokenId = ownedTokens[0];
        onchainBond = paco.getBond(mintedTokenId);
        onchainPrice = paco.getPrice(mintedTokenId);
    }

    function testBondCanBeIncreased() public {
        vm.prank(tokenWhale);
        paco.increaseBond(mintedTokenId, oneETH * 2);
        uint256 newBond = paco.getBond(mintedTokenId);
        assertEq(newBond, onchainBond + oneETH * 2);
    }

    function testBondCanBeDecreased() public {
        vm.prank(tokenWhale);
        paco.decreaseBond(mintedTokenId, oneETH);
        uint256 newBond = paco.getBond(mintedTokenId);
        assertEq(newBond, onchainBond - oneETH);
    }

    function testFailBondCanNotBeDecreasedBelowZero() public {
        vm.prank(tokenWhale);
        paco.decreaseBond(mintedTokenId, oneETH * 100);
    }

    function testPriceCanBeIncreased() public {
        vm.prank(tokenWhale);
        paco.increaseStatedPrice(mintedTokenId, oneETH * 2);
        uint256 newPrice = paco.getPrice(mintedTokenId);
        assertEq(newPrice, onchainPrice + oneETH * 2);
    }

    function testPriceCanBeDecreased() public {
        vm.prank(tokenWhale);
        paco.decreaseStatedPrice(mintedTokenId, oneETH);
        uint256 newPrice = paco.getPrice(mintedTokenId);
        assertEq(newPrice, onchainPrice - oneETH);
    }

    function testFailPriceCanNotBeIncreasedBeyondBond() public {
        vm.prank(tokenWhale);
        paco.increaseStatedPrice(mintedTokenId, oneETH * 100);
    }

    function testPriceAndBondBeIncreased() public {
        vm.prank(tokenWhale);
        paco.alterStatedPriceAndBond(
            mintedTokenId,
            int256(oneETH),
            int256(oneETH * 2)
        );
        uint256 newBond = paco.getBond(mintedTokenId);
        uint256 newPrice = paco.getPrice(mintedTokenId);
        assertEq(newPrice, onchainPrice + oneETH);
        assertEq(newBond, onchainBond + oneETH * 2);
    }

    // TODO add remaining cases later
}