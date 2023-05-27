// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PacoToken.sol";
import "./PacoTokenEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PacoExample is PacoTokenEnumerable, ReentrancyGuard {
    uint256 public constant mintPrice = 1;
    uint256 public constant MAX_SUPPLY = 10000;

    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => bool) internal authorizedForTransfer;

    // Token name
    string private _name;
    // Token symbol
    string private _symbol;
    string internal baseURI;
    uint256 internal fee;

    constructor(
        address tokenAddress,
        address withdrawAddress,
        uint256 selfAssessmentRate
    ) PacoTokenEnumerable(tokenAddress, withdrawAddress, selfAssessmentRate) {
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
        _mint(numberOfTokens, msg.sender, mintIndex, price, subscriptionPool);
    }

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 subscriptionPoolAmount
    ) external override nonReentrant {
        if (ownerOf(tokenId) == msg.sender) revert ClaimingOwnNFT();
        authorizedForTransfer[tokenId] = true;
        _buyToken(tokenId, newPrice, subscriptionPoolAmount);
        authorizedForTransfer[tokenId] = false;
    }

    function _mint(
        uint256 numberOfTokens,
        address sender,
        uint256 index,
        uint256 price,
        uint256 subscriptionPool
    ) private {
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _mint(sender, index + i, price, subscriptionPool);
        }
    }

    function setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) external virtual onlyOwner {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI set of nonexistent token"
        );
        _tokenURIs[tokenId] = _tokenURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return _tokenURIs[tokenId];
    }

    function _tokenIsAuthorizedForTransfer(
        uint256 tokenId
    ) internal view override returns (bool) {
        return authorizedForTransfer[tokenId];
    }
}
