// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

//inspired by ERC721 and ERC721Enumerable
interface IPacoToken {
    event Transfer(address from, address to, uint256 tokenId);
    event NewPriceSubscriptionPoolSet(
        uint256 tokenId,
        uint256 price,
        uint256 subscriptionPool
    );
    event NewSubscriptionRateSet(uint256 subscriptionRate);
    event NewMinimumPoolRatioSet(uint256 newPoolRatio);

    event Approval(
        address indexed _owner,
        address indexed _approved,
        uint256 indexed _tokenId
    );

    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function getSubscriptionPoolRemaining(
        uint256 _tokenId
    ) external view returns (uint256);

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

    function transferFrom(address from, address to, uint256 tokenId) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(
        uint256 tokenId
    ) external view returns (address operator);

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 subscriptionPoolAmount
    ) external;

    function alterStatedPriceAndSubscriptionPool(
        uint256 _tokenId,
        int256 priceDelta,
        int256 subscriptionPoolDelta
    ) external;

    function increaseSubscriptionPool(uint256 tokenId, uint256 amount) external;

    function decreaseSubscriptionPool(uint256 tokenId, uint256 amount) external;

    function increaseStatedPrice(uint256 tokenId, uint256 amount) external;

    function decreaseStatedPrice(uint256 tokenId, uint256 amount) external;
}
