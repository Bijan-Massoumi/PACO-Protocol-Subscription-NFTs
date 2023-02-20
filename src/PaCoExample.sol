// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PaCoToken.sol";

contract PaCoExample is PaCoToken {
    uint256 public constant mintPrice = 30000000000000000; //0.03 ETH
    uint256 public constant MAX_SUPPLY = 10000;
    bool public saleIsActive;

    mapping(uint256 => string) internal IPFS_CIDs;
    // Token name
    string private _name;
    // Token symbol
    string private _symbol;
    string internal baseURI;
    uint256 internal fee;
    bool revealed;

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
        require(saleIsActive, "Sale must be active to mint");
        require(
            totalSupply() + numberOfTokens <= MAX_SUPPLY,
            "Purchase would exceed max supply"
        );
        uint256 mintIndex = totalSupply();
        _mint(numberOfTokens, msg.sender, mintIndex, price, bond);
    }

    function setSaleStatus(bool value) external onlyOwner {
        saleIsActive = value;
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

        return
            bytes(IPFS_CIDs[tokenId]).length > 0
                ? string(abi.encodePacked(baseURI, IPFS_CIDs[tokenId]))
                : "ipfs://QmVXMMj5eBikicjViQLtqJDVVgupbFr3miFeo2pZmCX2kC";
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

    function setTokenCID(uint256 tokenId, string memory tokenCID)
        public
        onlyOwner
    {
        IPFS_CIDs[tokenId] = tokenCID;
    }

    function setTokenCIDs(uint256[] memory tokenIds, string[] memory tokenCIDs)
        public
        onlyOwner
    {
        require(tokenIds.length <= 100, "Limit 100 tokenIds");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IPFS_CIDs[tokenIds[i]] = tokenCIDs[i];
        }
    }
}
