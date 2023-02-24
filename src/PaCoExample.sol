// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PaCoToken.sol";

contract PaCoExample is PaCoToken {
    uint256 public constant mintPrice = 30000000000000000; //0.03 ETH
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
        uint16 selfAssessmentRate
    ) PaCoToken(tokenAddress, withdrawAddress, selfAssessmentRate) {
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
