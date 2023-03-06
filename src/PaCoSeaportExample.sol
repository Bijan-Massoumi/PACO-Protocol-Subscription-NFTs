// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PacoToken.sol";
import "./SeaportPacoToken.sol";

contract PacoSeaportExample is SeaportPacoToken {
    uint256 public constant mintPrice = 1;
    uint256 public constant MAX_SUPPLY = 10000;

    // Token name
    string private _name;
    // Token symbol
    string private _symbol;
    string internal baseURI;
    uint256 internal fee;

    constructor(
        address tokenAddress,
        address withdrawAddress,
        uint16 selfAssessmentRate,
        address seaportAddress
    )
        SeaportPacoToken(
            tokenAddress,
            withdrawAddress,
            selfAssessmentRate,
            seaportAddress
        )
    {
        _name = "Example";
        _symbol = "EXE";
    }

    function mint(
        uint256 numberOfTokens,
        uint256 price,
        uint256 subscriptionPool
    ) external {
        require(
            totalSupply() + numberOfTokens <= MAX_SUPPLY,
            "Purchase would exceed max supply"
        );
        uint256 mintIndex = totalSupply();
        _mint(mintIndex, numberOfTokens, msg.sender, price, subscriptionPool);
    }

    function _mint(
        uint256 start,
        uint256 numberOfTokens,
        address sender,
        uint256 price,
        uint256 subscriptionPool
    ) private {
        for (uint256 i = start; i < start + numberOfTokens; i++) {
            _mint(sender, i, price, subscriptionPool);
        }
    }
}
