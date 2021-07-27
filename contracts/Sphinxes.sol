// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CommonPartialToken.sol";

struct DnaData {
    uint248 dna;
    uint8 specialId;
}

contract Sphinxes is CommonPartialToken {
    uint256 public constant sphinxPrice = 30000000000000000; //0.03 ETH
    uint256 public constant MAX_SPHINXES = 10000;
    uint256 public MAX_SPECIAL = 9;
    uint256 public constant NUM_TRAITS = 6;
    bool public saleIsActive;
    uint256 internal nonce;

    mapping(uint256 => string) internal IPFS_CIDs;
    // Token name
    string private _name;
    // Token symbol
    string private _symbol;
    string internal baseURI;

    uint16[][NUM_TRAITS] private traitProbs;
    mapping(uint256 => DnaData) tokenDna;

    constructor(
        address currency,
        address treasuryContractAddress,
        uint16 interestRateToSet,
        uint16[] memory earsHats_p,
        uint16[] memory mouth_p,
        uint16[] memory eyes_p,
        uint16[] memory attire_p,
        uint16[] memory stance_p,
        uint16[] memory item_p
    ) CommonPartialToken(currency, treasuryContractAddress, interestRateToSet) {
        saleIsActive = false;
        traitProbs[0] = earsHats_p;
        traitProbs[1] = mouth_p;
        traitProbs[2] = eyes_p;
        traitProbs[3] = attire_p;
        traitProbs[4] = stance_p;
        traitProbs[5] = item_p;
        nonce = 15;
        _name = "Sphinxes";
        _symbol = "SPS";
    }

    function mintSphinx(
        uint256 numberOfTokens,
        uint256 price,
        uint256 bond
    ) external {
        require(saleIsActive, "Sale must be active to mint Sphinx");
        require(
            totalSupply() + numberOfTokens <= MAX_SPHINXES,
            "Purchase would exceed max supply of Sphinxes"
        );
        uint256 mintIndex = totalSupply();
        _mintSphinx(numberOfTokens, msg.sender, mintIndex, price, bond);
    }

    function setSaleStatus(bool value) external onlyOwner {
        saleIsActive = value;
    }

    function _mintSphinx(
        uint256 numberOfTokens,
        address sender,
        uint256 tokenId,
        uint256 price,
        uint256 bond
    ) private {
        for (uint256 i = 0; i < numberOfTokens; i++) {
            tokenDna[tokenId] = DnaData(
                uint248(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                nonce++,
                                block.difficulty,
                                block.timestamp,
                                sender
                            )
                        )
                    )
                ),
                //will be set after mint sells out
                0
            );
            _mint(sender, tokenId, price, bond);
        }
    }

    function getTraitsForToken(uint256 tokenId) external view {
        uint8[] memory traits = new uint8[](NUM_TRAITS);
        DnaData memory tokenData = tokenDna[tokenId];
        uint248 dna = tokenData.dna;
        require(dna > 0);
        for (uint256 i = 0; i < NUM_TRAITS; i++) {
            if (tokenData.specialId > 0) {
                traits[i] = uint8(100 + tokenData.specialId);
            } else {
                uint16 currentTraitDna = uint16(dna);
                traits[i] = _determineTrait(currentTraitDna, traitProbs[i]);
                dna >>= 16;
            }
        }
    }

    function _determineTrait(uint16 traitDna, uint16[] memory trait_p)
        private
        pure
        returns (uint8)
    {
        for (uint256 i = 0; i < trait_p.length; i++) {
            if (traitDna < trait_p[i]) {
                return uint8(i);
            }
        }
        revert();
    }

    function authorizedTreasuryMint(
        address recipient,
        uint256 initialStatedPrice,
        uint256 initialBond
    ) external onlyTreasury {
        _mintSphinx(
            1,
            recipient,
            totalSupply(),
            initialStatedPrice,
            initialBond
        );
    }

    function authorizedTreasuryBurn(uint256 tokenId) external onlyTreasury {
        _burnToken(tokenId);
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
