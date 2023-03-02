// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PaCoToken.sol";
import "forge-std/Test.sol";
import {ConsiderationItem, CriteriaResolver, AdvancedOrder, OfferItem, OrderType, ItemType, OrderType, OrderParameters} from "./SeaportStructs.sol";
import {SeaportInterface} from "./SeaportInterface.sol";

struct OwnerOwnedAmount {
    address owner;
    uint256 refund;
    uint256 owed;
    uint256 payed;
}

abstract contract SeaportPaCoToken is PaCoToken {
    // only supports seaport 1.1
    address seaportAddress;
    // tokenID to authroized bool
    mapping(uint256 => bool) internal authorizedForTransfer;
    using SafeERC20 for IERC20;

    // Errors --------------------------------------------

    error SeaportSwapFailed();
    error NonPacoToken();
    error FufillerSameAsTokenOwner();
    error NonStaticAmount();
    error InsufficientOwnerPayment();
    error InsufficientZonePayment();
    error NonExactBondAmount();
    error UnknownRecipient();

    constructor(
        address tokenAddress,
        address withdrawAddress,
        uint16 selfAssessmentRate,
        address _seaportAddress
    ) PaCoToken(tokenAddress, withdrawAddress, selfAssessmentRate) {
        seaportAddress = _seaportAddress;
        bondToken.approve(seaportAddress, 2**256 - 1);
    }

    // todo add bond refund to order
    function fulfillOrder(
        OfferItem[] calldata offer, // 0x40
        ConsiderationItem[] calldata consideration, // 0x60
        uint256[] calldata newStatedPrices,
        uint256[] calldata newBondAmounts
    ) external payable returns (bool fulfilled) {
        // verify consideration and offer
        uint256[] memory offerTokenIds;
        uint256 otiSize = 0;
        OwnerOwnedAmount[] memory amountDueToTokenOwners;
        uint256 amountDueSize;
        uint256 totalSenderCollect;
        (
            offerTokenIds,
            otiSize,
            amountDueToTokenOwners,
            amountDueSize,
            totalSenderCollect
        ) = _preprocessOffer(offer, msg.sender);
        _verifyConsideration(
            consideration,
            amountDueToTokenOwners,
            amountDueSize
        );

        // collect payment from msg.sender
        for (uint256 i = 0; i < newBondAmounts.length; i++) {
            totalSenderCollect == newBondAmounts[i];
        }
        bondToken.safeTransferFrom(
            msg.sender,
            address(this),
            totalSenderCollect
        );

        // fulfill order and swap assets
        for (uint256 i = 0; i < otiSize; i++) {
            authorizedForTransfer[offerTokenIds[i]] = true;
            _transferAdmin(
                ownerOf(offerTokenIds[i]),
                address(this),
                offerTokenIds[i]
            );
            // TODO change to operator approval
            _approve(seaportAddress, offerTokenIds[i]);
        }
        _fufillOrder(offer, consideration);

        // update bondInfo for each token transferred
        uint256 totalbond = 0;
        for (uint256 i = 0; i < otiSize; i++) {
            totalbond += newBondAmounts[i];
            // reverts if bond too little
            _postBond(
                msg.sender,
                offerTokenIds[i],
                newStatedPrices[i],
                newBondAmounts[i]
            );
            authorizedForTransfer[offerTokenIds[i]] = false;
        }

        return true;
    }

    function _fufillOrder(
        OfferItem[] calldata offer, // 0x40
        ConsiderationItem[] calldata consideration // 0x60
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

    function _preprocessOffer(OfferItem[] memory offer, address caller)
        internal
        view
        returns (
            uint256[] memory,
            uint256,
            // positionally aligns with offerTokenIds
            OwnerOwnedAmount[] memory,
            uint256,
            uint256
        )
    {
        uint256 totalPrice = 0;
        // create max length arrays
        uint256 otiSize = 0;
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
            if (owner == caller) revert FufillerSameAsTokenOwner();

            uint256 price;
            uint256 bond;
            uint256 fees;
            (price, bond, fees) = _getPriceBondFees(
                offerItem.identifierOrCriteria
            );
            offerTokenIds[otiSize++] = offerItem.identifierOrCriteria;

            // calculate amount due to token owners of offer
            bool found = false;
            for (uint256 j = 0; j < amountDueToTokenOwners.length; j++) {
                if (amountDueToTokenOwners[j].owner == owner) {
                    amountDueToTokenOwners[j].refund += bond;
                    amountDueToTokenOwners[j].owed += price;
                    found = true;
                    break;
                }
            }
            if (!found) {
                amountDueToTokenOwners[ooaSize++] = OwnerOwnedAmount(
                    owner,
                    bond,
                    price,
                    0
                );
            }
            found = false;
            totalPrice += price;
        }
        return (
            offerTokenIds,
            otiSize,
            amountDueToTokenOwners,
            ooaSize,
            totalPrice
        );
    }

    function _verifyConsideration(
        ConsiderationItem[] memory consideration,
        OwnerOwnedAmount[] memory amountDueToTokenOwners,
        uint256 amountDueSize
    ) internal view {
        for (uint256 i = 0; i < consideration.length; i++) {
            ConsiderationItem memory considerationItem = consideration[i];
            if (considerationItem.startAmount != considerationItem.endAmount)
                revert NonStaticAmount();

            bool sendingToKnownAddr = false;
            for (uint256 j = 0; j < amountDueSize; j++) {
                if (
                    amountDueToTokenOwners[j].owner ==
                    considerationItem.recipient &&
                    considerationItem.token == address(bondToken)
                ) {
                    amountDueToTokenOwners[j].payed += considerationItem
                        .endAmount;
                    sendingToKnownAddr = true;
                    break;
                }
            }
            if (!sendingToKnownAddr) revert UnknownRecipient();
        }
        for (uint256 i = 0; i < amountDueToTokenOwners.length; i++) {
            if (
                amountDueToTokenOwners[i].owed > amountDueToTokenOwners[i].payed
            ) revert InsufficientOwnerPayment();
        }
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
