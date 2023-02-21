// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./PaCoTokenEnumerable.sol";
import "./BondTracker.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

contract PaCoToken is PaCoTokenEnumerable, BondTracker {
    using Address for address;
    using SafeERC20 for IERC20;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 creatorFees;
    IERC20 bondToken;
    address withdrawAddress;

    constructor(
        address _erc20Address,
        address _withdrawAddress,
        uint16 _selfAssessmentRate
    ) Ownable() BondTracker(_selfAssessmentRate) {
        bondToken = IERC20(_erc20Address);
        withdrawAddress = _withdrawAddress;
    }

    // External functions ------------------------------------------------------

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

        uint256 feesToReap;
        uint256 liquidationStartedAt;
        uint256 bondRemaining;

        BondInfo memory currentOwnersBond = _bondInfosAtLastCheckpoint[tokenId];
        (
            bondRemaining,
            feesToReap,
            liquidationStartedAt
        ) = _getCurrentBondInfoForToken(currentOwnersBond);

        if (liquidationStartedAt != 0) {
            uint256 buyPrice = SafUtils.getLiquidationPrice(
                currentOwnersBond.statedPrice,
                block.timestamp - liquidationStartedAt,
                halfLife
            );
            bondToken.safeTransferFrom(
                msg.sender,
                currentOwnerAddress,
                buyPrice
            );
        } else {
            bondToken.safeTransferFrom(
                msg.sender,
                currentOwnerAddress,
                currentOwnersBond.statedPrice
            );
        }

        _bondToBeReturnedToAddress[currentOwnerAddress] += bondRemaining;
        creatorFees += feesToReap;

        _swapAndPostBond(
            currentOwnerAddress,
            msg.sender,
            msg.sender,
            tokenId,
            newPrice,
            bondAmount
        );
    }

    function isBeingLiquidated(uint256 tokenId)
        external
        view
        override
        returns (bool)
    {
        uint256 liquidationStartedAt = getLiquidationStartedAt(tokenId);
        return liquidationStartedAt != 0;
    }

    function alterStatedPriceAndBond(
        uint256 _tokenId,
        int256 priceDelta,
        int256 bondDelta
    ) external override {
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "ERC721: alterStatedPriceAndBond caller is not owner nor approved"
        );
        _alterStatedPriceAndBond(_tokenId, bondDelta, priceDelta);
    }

    function increaseBond(uint256 tokenId, uint256 amount) external override {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "PaCo: increaseBond caller is not owner nor approved"
        );
        _alterStatedPriceAndBond(tokenId, int256(amount), 0);
    }

    function decreaseBond(uint256 tokenId, uint256 amount) external override {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "PaCo: decreaseBond caller is not owner nor approved"
        );
        _alterStatedPriceAndBond(tokenId, -int256(amount), 0);
    }

    function increaseStatedPrice(uint256 tokenId, uint256 amount)
        external
        override
    {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "PaCo: increaseStatedPrice caller is not owner nor approved"
        );
        _alterStatedPriceAndBond(tokenId, 0, int256(amount));
    }

    function decreaseStatedPrice(uint256 tokenId, uint256 amount)
        external
        override
    {
        require(
            _isApprovedOrOwner(msg.sender, tokenId),
            "PaCo: decreaseStatedPrice caller is not owner nor approved"
        );
        _alterStatedPriceAndBond(tokenId, 0, -int256(amount));
    }

    function withdrawBondRefund() external {
        bondToken.safeTransfer(
            msg.sender,
            _bondToBeReturnedToAddress[msg.sender]
        );
    }

    function reapAndWithdrawFees(uint256[] calldata tokenIds) external {
        reapSafForTokenIds(tokenIds);
        withdrawAccumulatedFees();
    }

    function viewBondRefund(address addr) external view returns (uint256) {
        return _bondToBeReturnedToAddress[addr];
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

    function burnToken(uint256 tokenId) external {
        require(
            ownerOf(tokenId) == msg.sender,
            "Cannot burn token that sender doesnt own"
        );
        _burnToken(tokenId);
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
                SafUtils.getLiquidationPrice(
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

    function setEscrowIntent(
        uint256 tokenId,
        uint256 price,
        uint256 bond,
        uint256 expiry
    ) external override {
        require(_exists(tokenId));
        require(
            ownerOf(tokenId) != msg.sender,
            "Cannot set an escrow for a token you own"
        );

        _setEscrowIntent(tokenId, price, bond, expiry);
    }

    function getIntent(uint256 tokenId, address receiver)
        external
        view
        returns (EscrowIntentToReceive memory)
    {
        return escrowIntentToReceive[receiver][tokenId];
    }

    // Public functions ------------------------------------------------------

    function reapSafForTokenIds(uint256[] calldata tokenIds) public {
        uint256 netFees = 0;
        uint256 feesToReap;
        uint256 bondRemaining;
        uint256 liquidationStartedAt;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                _exists(tokenIds[i]),
                "token to reap fees for doesnt exist"
            );
            BondInfo storage currBondInfo = _bondInfosAtLastCheckpoint[
                tokenIds[i]
            ];
            (
                bondRemaining,
                feesToReap,
                liquidationStartedAt
            ) = _getCurrentBondInfoForToken(currBondInfo);
            currBondInfo.bondRemaining = bondRemaining;
            currBondInfo.lastModifiedAt = block.timestamp;
            currBondInfo.liquidationStartedAt = liquidationStartedAt;
            netFees += feesToReap;
        }
        creatorFees += netFees;
    }

    function withdrawAccumulatedFees() public {
        bondToken.safeTransfer(withdrawAddress, creatorFees);
        creatorFees = 0;
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

    /**
     * @dev See {PaCo-approve}.
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
     * @dev See {PaCo-getApproved}.
     */
    function getApproved(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        require(_exists(tokenId), "PaCo: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {PaCo-setApprovalForAll}.
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
     * @dev See {PaCo-isApprovedForAll}.
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

    /**
     * @dev See {PaCo-tokenOfOwnerByIndex}.
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
     * @dev See {PaCo-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {PaCo-tokenByIndex}.
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

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        _safeTransfer(from, to, tokenId, _data);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "Common Partial: transfer caller is not owner nor approved"
        );
        _transfer(from, to, tokenId);
    }

    // Internal functions ------------------------------------------------------

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
        require(to != address(0), "PaCo: mint to the zero address");
        require(!_exists(tokenId), "Token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);
        _balances[to] += 1;
        _owners[tokenId] = to;
        BondInfo storage bondInfoRef = _bondInfosAtLastCheckpoint[tokenId];
        _persistNewBondInfo(bondInfoRef, initialStatedPrice, bondAmount);
        bondToken.safeTransferFrom(to, address(this), bondAmount);
        emit Transfer(address(0), to, tokenId);
        emit NewPriceSet(to, tokenId, initialStatedPrice);
    }

    function _alterStatedPriceAndBond(
        uint256 _tokenId,
        int256 bondDelta,
        int256 priceDelta
    ) internal {
        uint256 feesToReap;
        uint256 amountToTransfer;
        BondInfo storage lastBondInfo = _bondInfosAtLastCheckpoint[_tokenId];
        uint256 lastPrice = lastBondInfo.statedPrice;
        (feesToReap, amountToTransfer) = _refreshAndModifyExistingBondInfo(
            lastBondInfo,
            bondDelta,
            priceDelta
        );
        if (lastPrice != lastBondInfo.statedPrice) {
            emit NewPriceSet(
                ownerOf(_tokenId),
                _tokenId,
                lastBondInfo.statedPrice
            );
        }

        creatorFees += feesToReap;
        if (amountToTransfer > 0)
            bondToken.safeTransferFrom(
                ownerOf(_tokenId),
                address(this),
                amountToTransfer
            );
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _burnToken(uint256 _tokenId) internal {
        address owner = ownerOf(_tokenId);
        _beforeTokenTransfer(owner, address(0), _tokenId);
        // Clear approvals
        _approve(address(0), _tokenId);
        _balances[owner] -= 1;
        delete _owners[_tokenId];
        delete _bondInfosAtLastCheckpoint[_tokenId];
        emit Transfer(owner, address(0), _tokenId);
    }

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

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        address currentOwnerAddress = ownerOf(tokenId);
        require(
            currentOwnerAddress == from,
            "ERC721: transfer of token that is not own"
        );
        require(to != address(0), "ERC721: transfer to the zero address");

        uint256 bondRemaining;
        uint256 feesToReap;
        EscrowIntentToReceive
            memory recipientEscrowInfo = escrowIntentToReceive[to][tokenId];
        require(
            recipientEscrowInfo.expiry > block.timestamp,
            "Intent to receive expired."
        );

        BondInfo memory currentOwnersBond = _bondInfosAtLastCheckpoint[tokenId];
        (bondRemaining, feesToReap, ) = _getCurrentBondInfoForToken(
            currentOwnersBond
        );

        _bondToBeReturnedToAddress[currentOwnerAddress] += bondRemaining;
        creatorFees += feesToReap;

        _swapAndPostBond(
            currentOwnerAddress,
            to,
            to,
            tokenId,
            recipientEscrowInfo.statedPrice,
            recipientEscrowInfo.bondToPost
        );

        delete escrowIntentToReceive[to][tokenId];
    }

    function _swapAndPostBond(
        address from,
        address to,
        address payer,
        uint256 tokenId,
        uint256 newPrice,
        uint256 bondAmount
    ) internal {
        require(to != address(0), "ERC721: transfer to the zero address");

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _beforeTokenTransfer(from, to, tokenId);
        _balances[to] += 1;
        _balances[from] -= 1;
        _owners[tokenId] = to;

        BondInfo storage bondInfoRef = _bondInfosAtLastCheckpoint[tokenId];

        _persistNewBondInfo(bondInfoRef, newPrice, bondAmount);
        bondToken.safeTransferFrom(payer, address(this), bondAmount);
        emit Transfer(from, to, tokenId);
        emit NewPriceSet(to, tokenId, newPrice);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try
                IERC721Receiver(to).onERC721Received(
                    _msgSender(),
                    from,
                    tokenId,
                    _data
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver(to).onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}
