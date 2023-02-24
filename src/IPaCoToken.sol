// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

//inspired by ERC721 and ERC721Enumerable
interface IPaCoToken {
    event Transfer(address from, address to, uint256 _tokenId);

    event NewPriceBondSet(
        address owner,
        uint256 tokenId,
        uint256 price,
        uint256 bond
    );

    event Approval(
        address indexed _owner,
        address indexed _approved,
        uint256 indexed _tokenId
    );

    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function getBond(uint256 _tokenId) external view returns (uint256);

    function getPrice(uint256 _tokenId) external view returns (uint256);

    function getStatedPrice(uint256 _tokenId) external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(uint256 tokenId)
        external
        view
        returns (address operator);

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 bondAmount
    ) external;

    function alterStatedPriceAndBond(
        uint256 _tokenId,
        int256 priceDelta,
        int256 bondDelta
    ) external;

    function increaseBond(uint256 tokenId, uint256 amount) external;

    function decreaseBond(uint256 tokenId, uint256 amount) external;

    function increaseStatedPrice(uint256 tokenId, uint256 amount) external;

    function decreaseStatedPrice(uint256 tokenId, uint256 amount) external;
}
