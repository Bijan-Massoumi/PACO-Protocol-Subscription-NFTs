// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./CommonPartialTokenEnumerable.sol";
import "./BondTracker.sol";
import "./InterestUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract CommonPartialToken is CommonPartiallyOwnedEnumerable, BondTracker {
    using Address for address;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 interestToSendToTreasury;
    IERC20 erc20ToUse;

    constructor(
        address erc20Address,
        address treasuryContractToSet,
        uint16 interestRateToSet
    ) BondTracker(treasuryContractToSet) {
        erc20ToUse = IERC20(erc20Address);
        interestRate = interestRateToSet;
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

    function ownerOf(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        address owner = _owners[tokenId];
        require(owner != address(0), "owner query for nonexistent token");
        return owner;
    }

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 bondAmount
    ) external virtual override {
        address currentOwnerAddress = ownerOf(tokenId);
        require(
            currentOwnerAddress != msg.sender,
            "can't claim your own token."
        );

        uint256 interestToReap;
        uint256 liquidationStartedAt;
        uint256 bondRemaining;

        BondInfo memory currentOwnersBond = _bondInfosAtLastCheckpoint[tokenId];
        (
            bondRemaining,
            interestToReap,
            liquidationStartedAt
        ) = _getCurrentBondInfoForToken(currentOwnersBond);

        if (liquidationStartedAt != 0) {
            uint256 buyPrice = InterestUtils.getLiquidationPrice(
                currentOwnersBond.statedPrice,
                block.timestamp - liquidationStartedAt,
                halfLife
            );
            erc20ToUse.transferFrom(msg.sender, currentOwnerAddress, buyPrice);
        } else {
            erc20ToUse.transferFrom(
                msg.sender,
                currentOwnerAddress,
                currentOwnersBond.statedPrice
            );
        }

        _bondToBeReturnedToAddress[currentOwnerAddress] += bondRemaining;
        interestToSendToTreasury += interestToReap;

        _beforeTokenTransfer(currentOwnerAddress, msg.sender, tokenId);
        _balances[msg.sender] += 1;
        _balances[currentOwnerAddress] -= 1;
        _owners[tokenId] = msg.sender;

        _generateAndPersistNewBondInfo(tokenId, newPrice, bondAmount);

        erc20ToUse.transferFrom(msg.sender, address(this), bondAmount);
        emit Transfer(currentOwnerAddress, msg.sender, tokenId, newPrice);
    }

    function isBeingLiquidated(uint256 tokenId)
        external
        view
        override
        returns (bool)
    {
        uint256 interestToReap;
        uint256 liquidationStartedAt;
        uint256 bondRemaining;

        BondInfo memory currentOwnersBond = _bondInfosAtLastCheckpoint[tokenId];
        (
            bondRemaining,
            interestToReap,
            liquidationStartedAt
        ) = _getCurrentBondInfoForToken(currentOwnersBond);
        return liquidationStartedAt != 0;
    }

    function getLiquidationStartedAt(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        uint256 liquidationStartedAt;
        BondInfo memory currentOwnersBond = _bondInfosAtLastCheckpoint[tokenId];
        (, , liquidationStartedAt) = _getCurrentBondInfoForToken(
            currentOwnersBond
        );
        return liquidationStartedAt;
    }

    function alterStatedPriceAndBond(
        uint256 _tokenId,
        int256 bondDelta,
        int256 priceDelta
    ) external override {
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        uint256 interestToReap;
        uint256 amountToTransfer;
        BondInfo storage lastBondInfo = _bondInfosAtLastCheckpoint[_tokenId];
        (interestToReap, amountToTransfer) = _refreshAndModifyExistingBondInfo(
            lastBondInfo,
            bondDelta,
            priceDelta
        );

        interestToSendToTreasury += interestToReap;
        if (amountToTransfer > 0)
            erc20ToUse.transferFrom(
                ownerOf(_tokenId),
                address(this),
                amountToTransfer
            );
    }

    function reapInterestForTokenIds(uint256[] calldata tokenIds) external {
        uint256 netInterest = 0;
        uint256 interestToReap;
        uint256 bondRemaining;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                _exists(tokenIds[i]),
                "token to reap interest for doesnt exist"
            );
            BondInfo storage currBondInfo = _bondInfosAtLastCheckpoint[
                tokenIds[i]
            ];
            (bondRemaining, interestToReap, ) = _getCurrentBondInfoForToken(
                currBondInfo
            );
            currBondInfo.bondRemaining = bondRemaining;
            currBondInfo.lastModifiedAt = block.timestamp;
            netInterest += interestToReap;
        }
        interestToSendToTreasury += netInterest;
        moveAccumulatedFundsToTreasury();
    }

    function moveAccumulatedFundsToTreasury() public {
        erc20ToUse.transferFrom(
            address(this),
            _treasury,
            interestToSendToTreasury
        );
        interestToSendToTreasury = 0;
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        require(to != owner, "approval to current owner");

        require(
            msg.sender == owner || isApprovedForAll(owner, msg.sender),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        require(
            _exists(tokenId),
            "ERC721: approved query for nonexistent token"
        );

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved)
        public
        virtual
        override
    {
        require(operator != msg.sender, "ERC721: approve to caller");

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    function withdrawBondRefund() external {
        erc20ToUse.transferFrom(
            address(this),
            msg.sender,
            _bondToBeReturnedToAddress[msg.sender]
        );
    }

    function viewBondRefund(address addr) external view returns (uint256) {
        return _bondToBeReturnedToAddress[addr];
    }

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

    function getBond(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        uint256 bondRemaining;
        (bondRemaining, , ) = _getCurrentBondInfoForToken(
            _bondInfosAtLastCheckpoint[_tokenId]
        );

        return bondRemaining;
    }

    function getPrice(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        uint256 liquidationStartedAt;
        BondInfo memory bondInfo = _bondInfosAtLastCheckpoint[_tokenId];
        (, , liquidationStartedAt) = _getCurrentBondInfoForToken(bondInfo);
        if (liquidationStartedAt != 0) {
            return
                InterestUtils.getLiquidationPrice(
                    bondInfo.statedPrice,
                    block.timestamp - liquidationStartedAt,
                    halfLife
                );
        } else {
            return bondInfo.statedPrice;
        }
    }

    function getStatedPrice(uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        return _bondInfosAtLastCheckpoint[_tokenId].statedPrice;
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
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
        _beforeTokenTransfer(address(0), to, tokenId);
        _balances[to] += 1;
        _owners[tokenId] = to;

        _generateAndPersistNewBondInfo(tokenId, initialStatedPrice, bondAmount);
        erc20ToUse.transferFrom(to, address(this), bondAmount);
        emit Transfer(address(0), to, tokenId, initialStatedPrice);
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _burnToken(uint256 _tokenId) internal {
        address owner = ownerOf(_tokenId);
        _beforeTokenTransfer(owner, address(0), _tokenId);
        _balances[owner] -= 1;
        delete _owners[_tokenId];
        delete _bondInfosAtLastCheckpoint[_tokenId];
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

    function getTokenIdsForAddress(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 size = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }
}
