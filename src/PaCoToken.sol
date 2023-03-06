// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BondTracker.sol";
import "./IPaCoToken.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

abstract contract PaCoToken is IPaCoToken, BondTracker {
    using Address for address;
    using SafeERC20 for IERC20;

    // Mapping from token ID to owner address
    mapping(uint256 => address) internal _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    uint256 creatorFees;
    IERC20 bondToken;
    address withdrawAddress;
    //  If the token is being liquidated, the stated price will halve every halfLife period of time
    uint256 halfLife = 2 days;

    /// ============ Errors ============

    /// @notice Thrown if a user tries to claim an NFT they already own
    error ClaimingOwnNFT();
    /// @notice Thrown if sender is not approved or owner
    error IsNotApprovedOrOwner();
    /// @notice Thrown if sender is not owner
    error IsNotOwner();
    /// @notice Thrown if sender is setting an eschrow for an owned token
    error SettingEschrowForOwnedToken();
    /// @notice Thrown if token does not exist
    error TokenDoesntExist();
    /// @notice Thrown if zero address is passed
    error IsZeroAddress();
    /// @notice Thrown if approval is called on the current owner
    error ApprovalToCurrentOwner();

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
        if (ownerOf(tokenId) == _msgSender()) revert ClaimingOwnNFT();
        _buyToken(tokenId, newPrice, bondAmount);
    }

    function alterStatedPriceAndBond(
        uint256 tokenId,
        int256 priceDelta,
        int256 bondDelta
    ) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndBond(tokenId, bondDelta, priceDelta);
    }

    function increaseBond(uint256 tokenId, uint256 amount) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndBond(tokenId, int256(amount), 0);
    }

    function decreaseBond(uint256 tokenId, uint256 amount) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndBond(tokenId, -int256(amount), 0);
    }

    function increaseStatedPrice(uint256 tokenId, uint256 amount)
        external
        override
    {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndBond(tokenId, 0, int256(amount));
    }

    function decreaseStatedPrice(uint256 tokenId, uint256 amount)
        external
        override
    {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndBond(tokenId, 0, -int256(amount));
    }

    function reapAndWithdrawFees(uint256[] calldata tokenIds) external {
        reapSafForTokenIds(tokenIds);
        withdrawAccumulatedFees();
    }

    function getBond(uint256 tokenId) external view override returns (uint256) {
        if (!_exists(tokenId)) revert TokenDoesntExist();
        uint256 bondRemaining;
        (bondRemaining, , ) = _getCurrentBondInfoForToken(
            _bondInfosAtLastCheckpoint[tokenId]
        );

        return bondRemaining;
    }

    function burnToken(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert IsNotOwner();

        _burnToken(tokenId);
    }

    function setHalfLife(uint16 newHalfLife) external onlyOwner {
        halfLife = newHalfLife;
    }

    function getPrice(uint256 tokenId)
        external
        view
        override
        returns (uint256)
    {
        if (!_exists(tokenId)) revert TokenDoesntExist();

        uint256 liquidationStartedAt;
        BondInfo memory bondInfo = _bondInfosAtLastCheckpoint[tokenId];
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

    // Public functions ------------------------------------------------------

    function isBeingLiquidated(uint256 tokenId) public view returns (bool) {
        uint256 liquidationStartedAt = getLiquidationStartedAt(tokenId);
        return liquidationStartedAt != 0;
    }

    function reapSafForTokenIds(uint256[] calldata tokenIds) public {
        uint256 netFees = 0;
        uint256 feesToReap;
        uint256 bondRemaining;
        uint256 liquidationStartedAt;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!_exists(tokenIds[i])) revert TokenDoesntExist();

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
        if (owner == address(0)) revert IsZeroAddress();
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
        if (owner == address(0)) revert IsZeroAddress();
        return owner;
    }

    /**
     * @dev See {PaCo-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        if (to == owner) revert ApprovalToCurrentOwner();

        require(
            msg.sender == owner,
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

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
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
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "Common Partial: transfer caller is not owner nor approved"
        );
        _transfer(from, to, tokenId);
    }

    // Internal functions ------------------------------------------------------

    function _buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 bondAmount
    ) internal virtual {
        uint256 price;
        uint256 bond;
        uint256 fees;
        (price, bond, fees) = _getPriceBondFees(tokenId);

        address currentOwnerAddress = ownerOf(tokenId);
        bondToken.safeTransferFrom(msg.sender, currentOwnerAddress, price);
        bondToken.safeTransfer(currentOwnerAddress, bond);
        creatorFees += fees;

        _swapAndPostBond(
            currentOwnerAddress,
            msg.sender,
            msg.sender,
            tokenId,
            newPrice,
            bondAmount
        );
    }

    function _getPriceBondFees(uint256 tokenId)
        internal
        view
        virtual
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (!_exists(tokenId)) revert TokenDoesntExist();
        BondInfo memory currentOwnersBond = _bondInfosAtLastCheckpoint[tokenId];
        uint256 price = currentOwnersBond.statedPrice;
        uint256 feesToReap;
        uint256 liquidationStartedAt;
        uint256 bondRemaining;
        (
            bondRemaining,
            feesToReap,
            liquidationStartedAt
        ) = _getCurrentBondInfoForToken(currentOwnersBond);

        if (liquidationStartedAt != 0) {
            price = SafUtils.getLiquidationPrice(
                currentOwnersBond.statedPrice,
                block.timestamp - liquidationStartedAt,
                halfLife
            );
        }

        return (price, bondRemaining, feesToReap);
    }

    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

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
        return (spender == owner || getApproved(tokenId) == spender);
    }

    function _mint(
        address to,
        uint256 tokenId,
        uint256 initialStatedPrice,
        uint256 bondAmount
    ) internal virtual {
        require(!_exists(tokenId), "Token already minted");
        require(to != address(0), "PaCo: mint to the zero address");

        _beforeTokenTransfer(address(0), to, tokenId);
        _balances[to] += 1;
        _owners[tokenId] = to;

        BondInfo storage bondInfoRef = _bondInfosAtLastCheckpoint[tokenId];
        _persistNewBondInfo(bondInfoRef, initialStatedPrice, bondAmount);
        bondToken.safeTransferFrom(to, address(this), bondAmount);
        emit Transfer(address(0), to, tokenId);
        emit NewPriceBondSet(to, tokenId, initialStatedPrice, bondAmount);
    }

    function _alterStatedPriceAndBond(
        uint256 tokenId,
        int256 bondDelta,
        int256 priceDelta
    ) internal virtual {
        BondInfo storage lastBondInfo = _bondInfosAtLastCheckpoint[tokenId];
        uint256 feesToReap = _modifyBondInfo(
            lastBondInfo,
            bondDelta,
            priceDelta
        );
        creatorFees += feesToReap;

        emit NewPriceBondSet(
            ownerOf(tokenId),
            tokenId,
            lastBondInfo.statedPrice,
            lastBondInfo.bondRemaining
        );

        // if bond is increasing, transfer bond from owner to contract
        if (bondDelta > 0) {
            bondToken.safeTransferFrom(
                ownerOf(tokenId),
                address(this),
                uint256(bondDelta)
            );
            // if bond is decreasing, transfer bond refund to owner
        } else if (bondDelta < 0) {
            bondToken.safeTransfer(ownerOf(tokenId), uint256(-bondDelta));
        }
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _burnToken(uint256 _tokenId) internal virtual {
        address owner = ownerOf(_tokenId);
        _beforeTokenTransfer(owner, address(0), _tokenId);
        // Clear approvals
        _approve(address(0), _tokenId);
        _balances[owner] -= 1;
        delete _owners[_tokenId];
        delete _bondInfosAtLastCheckpoint[_tokenId];
        emit Transfer(owner, address(0), _tokenId);
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
    ) internal virtual {
        address currentOwnerAddress = ownerOf(tokenId);
        require(
            currentOwnerAddress == from,
            "ERC721: transfer of token that is not own"
        );
        require(to != address(0), "PaCo: transfer to the zero address");
        require(
            _tokenIsAuthorizedForTransfer(tokenId),
            "PaCo: token not authorized"
        );

        _beforeTokenTransfer(from, to, tokenId);
        // Check that tokenId was not transferred by `_beforeTokenTransfer` hook
        require(
            ownerOf(tokenId) == from,
            "PaCo: transfer from incorrect owner"
        );
        // Clear approvals from the previous owner
        delete _tokenApprovals[tokenId];
        unchecked {
            // `_balances[from]` cannot overflow for the same reason as described in `_burn`:
            // `from`'s balance is the number of token held, which is at least one before the current
            // transfer.
            // `_balances[to]` could overflow in the conditions described in `_mint`. That would require
            // all 2**256 token ids to be minted, which in practice is impossible.
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    function _swapAndPostBond(
        address from,
        address to,
        address payer,
        uint256 tokenId,
        uint256 newPrice,
        uint256 bondAmount
    ) internal virtual {
        _transfer(from, to, tokenId);
        bondToken.safeTransferFrom(payer, address(this), bondAmount);
        _postBond(to, tokenId, newPrice, bondAmount);
    }

    function _postBond(
        address addr,
        uint256 tokenId,
        uint256 newPrice,
        uint256 bondAmount
    ) internal virtual {
        BondInfo storage bondInfoRef = _bondInfosAtLastCheckpoint[tokenId];
        _persistNewBondInfo(bondInfoRef, newPrice, bondAmount);
        emit NewPriceBondSet(addr, tokenId, newPrice, bondAmount);
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

    /**
     * @dev Hook that is called after any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens were transferred to `to`.
     * - When `from` is zero, the tokens were minted for `to`.
     * - When `to` is zero, ``from``'s tokens were burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId
    ) internal virtual {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    function _tokenIsAuthorizedForTransfer(uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {}
}
