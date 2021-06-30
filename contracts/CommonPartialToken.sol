// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./CommonPartialTokenEnumerable.sol";
import "./BondTracker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";

contract CommonPartialToken is CommonPartiallyOwnedEnumerable, BondTracker {
    using Address for address;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    IERC20 erc20ToUse;

    constructor(address erc20Address) {
        erc20ToUse = IERC20(erc20Address);
    }

    function balanceOf(address owner)
        public
        view
        override
        returns (uint256 balance)
    {
        require(owner != address(0), "Balance query for the zero address");
        return _balances[owner];
    }

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 amountToIncreaseBondBy
    ) external virtual override {}

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index)
        public
        view
        virtual
        override
        returns (uint256)
    {
        require(
            index < balanceOf(owner),
            "ERC721Enumerable: owner index out of bounds"
        );
        return _ownedTokens[owner][index];
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index)
        public
        view
        virtual
        override
        returns (uint256)
    {
        require(
            index < totalSupply(),
            "ERC721Enumerable: global index out of bounds"
        );
        return _allTokens[index];
    }

    function _mint(
        address to,
        uint256 tokenId,
        uint256 initialStatedPrice,
        uint256 bondAmount
    ) internal virtual {
        require(
            to != address(0),
            "CommonPartialToken: mint to the zero address"
        );
        require(!_exists(tokenId), "CommonPartialToken: token already minted");

        uint256 remainingBond;
        uint256 interestToReap;
        uint256 liquidationStartedAt;

        uint256 totalStatedPrice = _getStatedPriceSum(to);
        (
            remainingBond,
            interestToReap,
            liquidationStartedAt
        ) = _reapInterestAndUpdateBond(to, totalStatedPrice);

        require(
            liquidationStartedAt == 0,
            "Token cannot be minted while being liquidated."
        );
        require(
            remainingBond + bondAmount >
                ((initialStatedPrice + totalStatedPrice) * minimumBond) / 10000,
            "Bond not large enough to cover 10% of the new total stated price."
        );

        _beforeTokenTransfer(address(0), to, tokenId);
        _balances[to] += 1;
        _owners[tokenId] = to;

        erc20ToUse.transferFrom(to, address.this, bondAmount);

        emit Transfer(address(0), to, tokenId, initialStatedPrice);
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) private {
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

    function _getTokenIdsForAddress(address owner)
        public
        view
        returns (uint256[] tokenIds)
    {
        for (uint256 i = 0; i < balanceOf(owner); i++) {
            tokenIds.push(tokenOfOwnerByIndex(owner, i));
        }
    }

    function _getStatedPriceSum(address owner)
        public
        view
        returns (uint256 totalStatedPrice)
    {
        for (uint256 i = 0; i < balanceOf(owner); i++) {
            totalStatedPrice += _tokenIdToStatedPrice[
                tokenOfOwnerByIndex(owner, i)
            ];
        }
    }
}
