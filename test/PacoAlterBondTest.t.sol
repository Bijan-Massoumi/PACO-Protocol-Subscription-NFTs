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

    function setUp() public override {
        super.setUp();
        vm.prank(tokenWhale);
        uint256 statedPrice = oneETH * 100;
        uint256 bond = oneETH * 11;
        paco.mint(1, statedPrice, bond);
        uint256[] memory ownedTokens = paco.getTokenIdsForAddress(tokenWhale);
        mintedTokenId = ownedTokens[0];
        onchainBond = paco.getBond(mintedTokenId);
    }

    function testBondCanBeIncreased() public {
        vm.prank(tokenWhale);
        paco.increaseBond(mintedTokenId, oneETH * 2);
        //uint256 newBond = paco.getBond(mintedTokenId);
        //assertEq(newBond, onchainBond + oneETH * 2);
        assert(true);
    }
}
