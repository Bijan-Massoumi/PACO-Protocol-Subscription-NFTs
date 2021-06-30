// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//inspired by ERC721 and ERC721Enumerable
interface CommonPartiallyOwned {
    event Transfer(address from, address to, uint256 _tokenId, uint256 price);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 amountToIncreaseBondBy
    ) external;

    function decreaseBond(uint256 amountToDecreaseBondBy) external;

    function increaseBond(uint256 amountToIncreaseBondBy) external;

    function getBond() external view;

    function getPrice() external view;

    function burnToken() external;

    function getStatedPrice() external view;

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function approve(address to, uint256 tokenId) external;

    function getApproved(uint256 tokenId)
        external
        view
        returns (address operator);
}
