// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CommonPartialToken.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract Sphinxes is CommonPartialToken, VRFConsumerBase {
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
    uint256 internal fee;
    bool revealed;
    bytes32 internal keyHash;
    event SphinxSeed(uint256 seed);

    uint8[][NUM_TRAITS] private traitProbs;
    uint256 seed = 0;

    constructor(
        // coordinator, Linkaddr, currency, treasuryContract
        address[] memory addressesToSet,
        bytes32 _keyHash,
        uint16 interestRateToSet,
        uint8[][NUM_TRAITS] memory traits_p
    )
        CommonPartialToken(
            addressesToSet[2],
            addressesToSet[3],
            interestRateToSet
        )
        VRFConsumerBase(addressesToSet[0], addressesToSet[1])
    {
        saleIsActive = false;
        traitProbs[0] = traits_p[0];
        traitProbs[1] = traits_p[1];
        traitProbs[2] = traits_p[2];
        traitProbs[3] = traits_p[3];
        traitProbs[4] = traits_p[4];
        traitProbs[5] = traits_p[5];
        nonce = 15;
        _name = "Sphinxes";
        _symbol = "SPS";
        fee = 2 * 10**18; // 2 LINK token
        keyHash = _keyHash[2];
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
            _mint(sender, tokenId, price, bond);
        }
    }

    function reveal() public onlyOwner {
        require(!revealed);
        require(LINK.balanceOf(address(this)) >= fee);
        requestRandomness(keyHash, fee);
        revealed = true;
    }

    /**
     * @dev receive random number from chainlink
     * @notice random number will greater than zero
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomNumber)
        internal
        override
    {
        if (randomNumber > 0) seed = randomNumber;
        else seed = 1;
        emit SphinxSeed(seed);
    }

    function getTraitsForToken(uint256 tokenId) external view {
        require(seed > 0, "Seed hasnt been set.");
        require(
            _exists(tokenId),
            "Cannot get the attributes for non-existent token."
        );
        uint8[] memory traits = new uint8[](NUM_TRAITS);
        uint256 dna = uint256(keccak256(abi.encodePacked(seed, tokenId)));
        for (uint256 i = 0; i < NUM_TRAITS; i++) {
            uint8 currentTraitDna = uint8(dna);
            traits[i] = _determineTrait(currentTraitDna, traitProbs[i]);
            dna >>= 8;
        }
    }

    function _determineTrait(uint8 traitDna, uint8[] memory trait_p)
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
