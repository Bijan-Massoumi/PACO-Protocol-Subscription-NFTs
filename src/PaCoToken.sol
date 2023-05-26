// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SubscriptionPoolTracker.sol";
import "./IPacoToken.sol";
import "./IPacoTokenErrors.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

abstract contract PacoToken is
    IPacoToken,
    SubscriptionPoolTracker,
    IPacoTokenErrors,
    Ownable
{
    using Address for address;
    using SafeERC20 for IERC20;

    // Mapping from token ID to owner address
    mapping(uint256 => address) internal _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    uint256 creatorFees;
    IERC20 subscriptionPoolToken;
    address withdrawAddress;

    constructor(
        address _erc20Address,
        address _withdrawAddress,
        uint256 _subscriptionRate
    ) Ownable() SubscriptionPoolTracker(2 days, _subscriptionRate) {
        subscriptionPoolToken = IERC20(_erc20Address);
        withdrawAddress = _withdrawAddress;
        emit NewSubscriptionRateSet(_subscriptionRate);
    }

    // External functions ------------------------------------------------------

    function buyToken(
        uint256 tokenId,
        uint256 newPrice,
        uint256 subscriptionPoolAmount
    ) external virtual override {
        if (ownerOf(tokenId) == _msgSender()) revert ClaimingOwnNFT();
        if (!_exists(tokenId)) revert TokenDoesntExist();
        _buyToken(tokenId, newPrice, subscriptionPoolAmount);
    }

    // Price Adjusting Functions -----------------------------------------------

    function alterStatedPriceAndSubscriptionPool(
        uint256 tokenId,
        int256 priceDelta,
        int256 subscriptionPoolDelta
    ) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndSubscriptionPool(
            tokenId,
            subscriptionPoolDelta,
            priceDelta
        );
    }

    function increaseSubscriptionPool(
        uint256 tokenId,
        uint256 amount
    ) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndSubscriptionPool(tokenId, int256(amount), 0);
    }

    function decreaseSubscriptionPool(
        uint256 tokenId,
        uint256 amount
    ) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndSubscriptionPool(tokenId, -int256(amount), 0);
    }

    function increaseStatedPrice(
        uint256 tokenId,
        uint256 amount
    ) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndSubscriptionPool(tokenId, 0, int256(amount));
    }

    function decreaseStatedPrice(
        uint256 tokenId,
        uint256 amount
    ) external override {
        if (!_isApprovedOrOwner(msg.sender, tokenId))
            revert IsNotApprovedOrOwner();

        _alterStatedPriceAndSubscriptionPool(tokenId, 0, -int256(amount));
    }

    function reapAndWithdrawFees(uint256[] calldata tokenIds) external {
        reapSafForTokenIds(tokenIds);
        withdrawAccumulatedFees();
    }

    // Paco paramter getters and setters ---------------------------------------

    function getSubscriptionRate() public view returns (uint256) {
        return subscriptionRate;
    }

    function setSubscriptionRate(
        uint256 newSubscriptionRate
    ) external onlyOwner {
        if (newSubscriptionRate > maxSubscriptionRate) {
            revert InvalidAssessmentFee();
        }
        if (newSubscriptionRate > maxSubscriptionRate) {
            revert InvalidAssessmentFee();
        }

        _setSubscriptionRate(newSubscriptionRate);
        emit NewSubscriptionRateSet(newSubscriptionRate);
    }

    function getMinimumPoolRatio() public view returns (uint256) {
        return minimumPoolRatio;
    }

    function setMinimumPoolRatio(
        uint256 newMinimumPoolRatio
    ) external onlyOwner {
        if (newMinimumPoolRatio > maxMinimumPoolRatio) {
            revert InvalidMininumBond();
        }

        _setMinimumPoolRatio(newMinimumPoolRatio);
        emit NewMinimumPoolRatioSet(newMinimumPoolRatio);
    }

    function getHalfLife() public view returns (uint256) {
        return halfLife;
    }

    function setHalfLife(uint256 newHalflife) external onlyOwner {
        _setHalfLife(newHalflife);
    }

    // Token Info Getters ------------------------------------------------------

    function getSubscriptionPoolRemaining(
        uint256 tokenId
    ) external view override returns (uint256) {
        if (!_exists(tokenId)) revert TokenDoesntExist();
        uint256 subscriptionPoolRemaining = _getSubscriptionPoolRemaining(
            tokenId
        );

        return subscriptionPoolRemaining;
    }

    function getPrice(
        uint256 tokenId
    ) external view override returns (uint256) {
        if (!_exists(tokenId)) revert TokenDoesntExist();
        return _getPrice(tokenId);
    }

    function getStatedPrice(
        uint256 _tokenId
    ) external view override returns (uint256) {
        return _getStatedPrice(_tokenId);
    }

    // burn
    function burnToken(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert IsNotOwner();
        _burnToken(tokenId);
    }

    // Public functions ------------------------------------------------------

    function getLiquidationStartedAt(
        uint256 tokenId
    ) public view returns (uint256) {
        return _getLiquidationStartedAt(tokenId);
    }

    function isBeingLiquidated(uint256 tokenId) public view returns (bool) {
        uint256 liquidationStartedAt = getLiquidationStartedAt(tokenId);
        return liquidationStartedAt != 0;
    }

    function reapSafForTokenIds(uint256[] calldata tokenIds) public {
        uint256 netFees = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!_exists(tokenIds[i])) revert TokenDoesntExist();
            netFees += _getFeesToCollectForToken(tokenIds[i]);
        }
        creatorFees += netFees;
    }

    function withdrawAccumulatedFees() public {
        subscriptionPoolToken.safeTransfer(withdrawAddress, creatorFees);
        creatorFees = 0;
    }

    function balanceOf(
        address owner
    ) public view override returns (uint256 balance) {
        if (owner == address(0)) revert IsZeroAddress();
        return _balances[owner];
    }

    function ownerOf(
        uint256 tokenId
    ) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert IsZeroAddress();
        return owner;
    }

    /**
     * @dev See {Paco-approve}.
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
     * @dev See {Paco-getApproved}.
     */
    function getApproved(
        uint256 tokenId
    ) public view virtual override returns (address) {
        require(_exists(tokenId), "Paco: approved query for nonexistent token");

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
        uint256 subscriptionPoolAmount
    ) internal virtual {
        uint256 price;
        uint256 subscriptionPool;
        uint256 fees;
        (price, subscriptionPool, fees) = _getPriceSubscriptionPoolFees(
            tokenId
        );

        address currentOwnerAddress = ownerOf(tokenId);
        subscriptionPoolToken.safeTransferFrom(
            msg.sender,
            currentOwnerAddress,
            price
        );
        subscriptionPoolToken.safeTransfer(
            currentOwnerAddress,
            subscriptionPool
        );
        creatorFees += fees;

        _swapAndPostSubscriptionPool(
            currentOwnerAddress,
            msg.sender,
            msg.sender,
            tokenId,
            newPrice,
            subscriptionPoolAmount
        );
    }

    // Internal paco parameter change functions -------------------------------

    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) internal view virtual returns (bool) {
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
        uint256 subscriptionPoolAmount
    ) internal virtual {
        require(!_exists(tokenId), "Token already minted");
        require(to != address(0), "Paco: mint to the zero address");

        _beforeTokenTransfer(address(0), to, tokenId);
        _balances[to] += 1;
        _owners[tokenId] = to;

        _persistNewSubscriptionPoolInfo(
            tokenId,
            initialStatedPrice,
            subscriptionPoolAmount,
            0
        );
        subscriptionPoolToken.safeTransferFrom(
            to,
            address(this),
            subscriptionPoolAmount
        );
        emit Transfer(address(0), to, tokenId);
        emit NewPriceSubscriptionPoolSet(
            tokenId,
            initialStatedPrice,
            subscriptionPoolAmount
        );
    }

    function _alterStatedPriceAndSubscriptionPool(
        uint256 tokenId,
        int256 subscriptionPoolDelta,
        int256 priceDelta
    ) internal virtual {
        uint256 feesToReap;
        uint256 newStatedPrice;
        uint256 newSubscriptionPool;
        (
            feesToReap,
            newStatedPrice,
            newSubscriptionPool
        ) = _updateStatedPriceAndSubPool(
            tokenId,
            subscriptionPoolDelta,
            priceDelta
        );
        creatorFees += feesToReap;

        emit NewPriceSubscriptionPoolSet(
            tokenId,
            newStatedPrice,
            newSubscriptionPool
        );

        // if subscriptionPool is increasing, transfer subscriptionPool from owner to contract
        if (subscriptionPoolDelta > 0) {
            subscriptionPoolToken.safeTransferFrom(
                ownerOf(tokenId),
                address(this),
                uint256(subscriptionPoolDelta)
            );
            // if subscriptionPool is decreasing, transfer subscriptionPool refund to owner
        } else if (subscriptionPoolDelta < 0) {
            subscriptionPoolToken.safeTransfer(
                ownerOf(tokenId),
                uint256(-subscriptionPoolDelta)
            );
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
        delete _subscriptionPoolInfosAtLastCheckpoint[_tokenId];
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
        require(to != address(0), "Paco: transfer to the zero address");
        require(
            _tokenIsAuthorizedForTransfer(tokenId),
            "Paco: token not authorized"
        );

        _beforeTokenTransfer(from, to, tokenId);
        // Check that tokenId was not transferred by `_beforeTokenTransfer` hook
        require(
            ownerOf(tokenId) == from,
            "Paco: transfer from incorrect owner"
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

    function _swapAndPostSubscriptionPool(
        address from,
        address to,
        address payer,
        uint256 tokenId,
        uint256 newPrice,
        uint256 subscriptionPoolAmount
    ) internal virtual {
        _transfer(from, to, tokenId);
        subscriptionPoolToken.safeTransferFrom(
            payer,
            address(this),
            subscriptionPoolAmount
        );
        _postSubscriptionPool(tokenId, newPrice, subscriptionPoolAmount);
    }

    function _postSubscriptionPool(
        uint256 tokenId,
        uint256 newPrice,
        uint256 subscriptionPoolAmount
    ) internal virtual {
        _persistNewSubscriptionPoolInfo(
            tokenId,
            newPrice,
            subscriptionPoolAmount,
            0
        );
        emit NewPriceSubscriptionPoolSet(
            tokenId,
            newPrice,
            subscriptionPoolAmount
        );
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

    function _tokenIsAuthorizedForTransfer(
        uint256 tokenId
    ) internal view virtual returns (bool) {}
}
