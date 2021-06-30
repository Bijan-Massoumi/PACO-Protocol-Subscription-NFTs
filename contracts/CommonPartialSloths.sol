// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CommonPartialToken.sol";

contract CommonPartialSloths is CommonPartialToken {
    uint256 latestTokenId = 1;

    constructor(address erc20Address) CommonPartialERC721(erc20Address) {}

    function mintSloth() external {
        _mint(msg.sender, latestTokenId);
        latestTokenId++;
    }
}
