// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PacoTokenEnumerable.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ConsiderationItem, CriteriaResolver, AdvancedOrder, OfferItem, OrderType, ItemType, OrderType, OrderParameters} from "./SeaportStructs.sol";
import {SeaportInterface} from "./SeaportInterface.sol";
import {ISeaportErrors} from "./ISeaportErrors.sol";

struct OwnerOwnedAmount {
    address owner;
    uint256 refund;
    uint256 owed;
    uint256 payed;
}

struct Tip {
    address recipient;
    uint256 amount;
}

abstract contract SeaportPacoToken is
    PacoTokenEnumerable,
    ISeaportErrors,
    ReentrancyGuard
{
    address seaportAddress;
    // tokenID to authorized bool
    mapping(uint256 => bool) internal authorizedForTransfer;
    mapping(uint256 => address) internal seaportOwner;
    using SafeERC20 for IERC20;

    // Errors --------------------------------------------

    constructor(
        address tokenAddress,
        address withdrawAddress,
        uint16 selfAssessmentRate,
        address _seaportAddress
    ) PacoTokenEnumerable(tokenAddress, withdrawAddress, selfAssessmentRate) {
        seaportAddress = _seaportAddress;
        subscriptionPoolToken.approve(seaportAddress, 2**256 - 1);
    }

    // todo add subscriptionPool refund to order. add to fufill order?
    function fulfillOrder(
        OfferItem[] calldata offer, // 0x40
        ConsiderationItem[] calldata consideration, // 0x60
        uint256[] calldata newStatedPrices,
        uint256[] calldata newSubscriptionPoolAmounts
    ) external payable nonReentrant returns (bool fulfilled) {
        // validate consideration and offer
        uint256[] memory offerTokenIds;
        uint256 offerTokenIdsSize = 0;
        OwnerOwnedAmount[] memory amountDueToTokenOwners;
        uint256 amountDueOwnersSize;
        uint256 senderFunds;
        (
            offerTokenIds,
            offerTokenIdsSize,
            amountDueToTokenOwners,
            amountDueOwnersSize,
            senderFunds
        ) = _preprocessOffer(offer);
        uint256 totalTips = _verifyConsideration(
            consideration,
            amountDueToTokenOwners,
            amountDueOwnersSize
        );

        // collect payment from msg.sender for purchased token subscriptionPools + tip payments
        senderFunds += totalTips;
        for (uint256 i = 0; i < newSubscriptionPoolAmounts.length; i++) {
            senderFunds += newSubscriptionPoolAmounts[i];
        }
        subscriptionPoolToken.safeTransferFrom(
            msg.sender,
            address(this),
            senderFunds
        );

        // fulfill order and swap assets
        for (uint256 i = 0; i < offerTokenIdsSize; i++) {
            _prepareTokenForSeaportTransfer(offerTokenIds[i]);
        }
        _fufillOrder(
            offer,
            _addRefundsToConsideration(consideration, amountDueToTokenOwners)
        );

        // update subscriptionPoolInfo for each token transferred
        uint256 totalsubscriptionPool = 0;
        for (uint256 i = 0; i < offerTokenIdsSize; i++) {
            totalsubscriptionPool += newSubscriptionPoolAmounts[i];
            // reverts if subscriptionPool too little
            _postSubscriptionPool(
                offerTokenIds[i],
                newStatedPrices[i],
                newSubscriptionPoolAmounts[i]
            );
            authorizedForTransfer[offerTokenIds[i]] = false;
        }

        return true;
    }

    function _fufillOrder(
        OfferItem[] memory offer, // 0x40
        ConsiderationItem[] memory consideration // 0x60
    ) internal {
        OrderParameters memory params = OrderParameters(
            address(this),
            address(this),
            offer,
            consideration,
            OrderType.FULL_RESTRICTED,
            block.timestamp,
            block.timestamp + 1 days,
            bytes32(0),
            123,
            bytes32(0),
            consideration.length
        );
        AdvancedOrder memory advancedOrder = AdvancedOrder(
            params,
            uint120(offer.length),
            uint120(offer.length),
            new bytes(0),
            new bytes(0)
        );

        SeaportInterface seaport = SeaportInterface(seaportAddress);
        if (
            !seaport.fulfillAdvancedOrder(
                advancedOrder,
                new CriteriaResolver[](0),
                bytes32(0),
                msg.sender
            )
        ) revert SeaportSwapFailed();
    }

    function _preprocessOffer(OfferItem[] memory offer)
        internal
        view
        returns (
            uint256[] memory,
            uint256,
            OwnerOwnedAmount[] memory,
            uint256,
            uint256
        )
    {
        uint256 totalPrice = 0;
        // create max length arrays
        uint256 offerTokenIdsSize = 0;
        uint256[] memory offerTokenIds = new uint256[](offer.length);

        uint256 ooaSize = 0;
        OwnerOwnedAmount[]
            memory amountDueToTokenOwners = new OwnerOwnedAmount[](
                offer.length
            );
        for (uint256 i = 0; i < offer.length; i++) {
            OfferItem memory offerItem = offer[i];
            address owner = ownerOf(offerItem.identifierOrCriteria);
            if (offerItem.token != address(this)) revert NonPacoToken();
            if (owner == msg.sender) revert FufillerSameAsTokenOwner();

            uint256 price;
            uint256 subscriptionPool;
            uint256 fees;
            (price, subscriptionPool, fees) = _getPriceSubscriptionPoolFees(
                offerItem.identifierOrCriteria
            );
            offerTokenIds[offerTokenIdsSize++] = offerItem.identifierOrCriteria;

            // calculate amount due to token owners of offer
            bool found = false;
            for (uint256 j = 0; j < amountDueToTokenOwners.length; j++) {
                if (amountDueToTokenOwners[j].owner == owner) {
                    amountDueToTokenOwners[j].refund += subscriptionPool;
                    amountDueToTokenOwners[j].owed += price;
                    found = true;
                    break;
                }
            }
            if (!found) {
                amountDueToTokenOwners[ooaSize++] = OwnerOwnedAmount(
                    owner,
                    subscriptionPool,
                    price,
                    0
                );
            }
            found = false;
            totalPrice += price;
        }

        return (
            offerTokenIds,
            offerTokenIdsSize,
            amountDueToTokenOwners,
            ooaSize,
            totalPrice
        );
    }

    function _verifyConsideration(
        ConsiderationItem[] memory consideration,
        OwnerOwnedAmount[] memory amountDueToTokenOwners,
        uint256 amountDueOwnersSize
    ) internal view returns (uint256 totalTip) {
        Tip[] memory tips = new Tip[](consideration.length);
        uint256 tipIdx = 0;
        for (uint256 i = 0; i < consideration.length; i++) {
            ConsiderationItem memory considerationItem = consideration[i];
            if (considerationItem.startAmount != considerationItem.endAmount)
                revert NonStaticAmount();
            if (considerationItem.token != address(subscriptionPoolToken))
                revert NonSubscriptionPoolToken();

            // check if payment is to offer token owner or a tip to an unknown address
            bool sendingToKnownAddr = false;
            for (uint256 j = 0; j < amountDueOwnersSize; j++) {
                if (
                    amountDueToTokenOwners[j].owner ==
                    considerationItem.recipient
                ) {
                    amountDueToTokenOwners[j].payed += considerationItem
                        .endAmount;
                    sendingToKnownAddr = true;
                    break;
                }
            }
            if (!sendingToKnownAddr) {
                tips[tipIdx++] = Tip(
                    considerationItem.recipient,
                    considerationItem.endAmount
                );
                totalTip += considerationItem.endAmount;
            }
        }

        // check that all owed amounts are paid
        for (uint256 i = 0; i < amountDueToTokenOwners.length; i++) {
            if (
                amountDueToTokenOwners[i].owed > amountDueToTokenOwners[i].payed
            ) revert InsufficientOwnerPayment();
        }
    }

    function _addRefundsToConsideration(
        ConsiderationItem[] memory consideration,
        OwnerOwnedAmount[] memory refunds
    ) internal view returns (ConsiderationItem[] memory) {
        ConsiderationItem[] memory result = new ConsiderationItem[](
            consideration.length + refunds.length
        );
        uint256 index = 0;

        for (uint256 i = 0; i < consideration.length; i++) {
            result[index] = consideration[i];
            index++;
        }

        for (uint256 i = 0; i < refunds.length; i++) {
            result[index] = ConsiderationItem(
                ItemType.ERC20,
                address(subscriptionPoolToken),
                0,
                refunds[i].refund,
                refunds[i].refund,
                payable(refunds[i].owner)
            );
            index++;
        }

        return result;
    }

    function _prepareTokenForSeaportTransfer(uint256 tokenId) internal {
        address currentOwner = ownerOf(tokenId);
        seaportOwner[tokenId] = currentOwner;
        _owners[tokenId] = address(this);
        authorizedForTransfer[tokenId] = true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        from;
        //solhint-disable-next-line max-line-length
        require(
            _msgSender() == seaportAddress,
            "Common Partial: transfer caller is not seaport"
        );
        address currentOwner = seaportOwner[tokenId];
        if (currentOwner == address(0)) revert InvalidOwner();

        _owners[tokenId] = currentOwner;
        _transfer(currentOwner, to, tokenId);
        delete seaportOwner[tokenId];
    }

    function _tokenIsAuthorizedForTransfer(uint256 tokenId)
        internal
        view
        override
        returns (bool)
    {
        return authorizedForTransfer[tokenId];
    }
}
