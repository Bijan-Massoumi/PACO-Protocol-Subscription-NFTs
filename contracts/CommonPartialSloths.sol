// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CommonPartialToken.sol";

contract CommonPartialSloths is CommonPartialToken {
    uint256 latestTokenId = 1;

    constructor(address erc20Address, uint16 interestRate)
        CommonPartialToken(erc20Address, interestRate)
    {}

    function mintSloth(uint256 statedPrice, uint256 bond) external {
        _mint(msg.sender, latestTokenId, statedPrice, bond);
        latestTokenId++;
    }
}
