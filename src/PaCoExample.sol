// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PaCoToken.sol";
import "./SeaportPaCoToken.sol";

contract PaCoExample is SeaportPaCoToken, ReentrancyGuard {
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
        SeaportPaCoToken(
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
        uint256 bond
    ) external {
        require(
            totalSupply() + numberOfTokens <= MAX_SUPPLY,
            "Purchase would exceed max supply"
        );
        uint256 mintIndex = totalSupply();
        _mint(numberOfTokens, msg.sender, mintIndex, price, bond);
    }

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 bondAmount
    ) external override nonReentrant {
        if (ownerOf(tokenId) == _msgSender()) revert ClaimingOwnNFT();
        authorizedForTransfer[tokenId] = true;
        _buyToken(tokenId, newPrice, bondAmount);
        authorizedForTransfer[tokenId] = false;
    }

    function _mint(
        uint256 numberOfTokens,
        address sender,
        uint256 tokenId,
        uint256 price,
        uint256 bond
    ) private {
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _mint(sender, tokenId, price, bond);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId, balanceOf(from));
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId, balanceOf(to));
        }
    }

    // standard erc721metadata methods.

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return "ipfs://QmVXMMj5eBikicjViQLtqJDVVgupbFr3miFeo2pZmCX2kC";
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }
}
