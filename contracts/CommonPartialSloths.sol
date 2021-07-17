// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CommonPartialToken.sol";

contract Sphinxes is CommonPartialToken {
    uint256 latestTokenId = 1;

    constructor(
        address erc20Address,
        uint16 interestRateToSet,
        uint16 mintAndBurnRateToSet
    ) CommonPartialToken(erc20Address, interestRateToSet) {}

    function mintSloth(uint256 statedPrice, uint256 bond) external {
        if (latestTokenId < 10000) {
            _mint(msg.sender, latestTokenId, statedPrice, bond);
            latestTokenId++;
        }
    }

    function authorizedTreasuryMint(
        address recipient,
        uint256 initialStatedPrice,
        uint256 initialBond
    ) external onlyTreasury {
        _mint(recipient, latestTokenId, initialStatedPrice, initialBond);
        latestTokenId++;
    }

    function authorizedTreasuryBurn(uint256 tokenId) external onlyTreasury {
        _burnToken(tokenId);
    }
}
