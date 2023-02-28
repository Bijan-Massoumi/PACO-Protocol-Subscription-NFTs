// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PaCoToken.sol";
import {ConsiderationItem, CriteriaResolver, AdvancedOrder, OfferItem, OrderType} from "./SeaportStructs.sol";
import {SeaportInterface} from "./SeaportInterface.sol";

struct TokenWithPrice {
    uint256 tokenId;
    uint256 price;
}

abstract contract SeaportPaCoToken is PaCoToken {
    // only supports seaport 1.1
    address seaportAddress;
    // tokenID to authroized bool
    mapping(uint256 => bool) internal authorizedForTransfer;

    // Errors --------------------------------------------

    error SeaportSwapFailed();
    error NotRestrictedFullOrder();
    error FufillerSameAsTokenOwner();
    error NonStaticAmount();
    error InsufficientOwnerPayment();
    error InsufficientZonePayment();
    error InvalidBondAmount();

    constructor(
        address tokenAddress,
        address withdrawAddress,
        uint16 selfAssessmentRate,
        address _seaportAddress
    ) PaCoToken(tokenAddress, withdrawAddress, selfAssessmentRate) {
        seaportAddress = _seaportAddress;
    }

    function fulfillAdvancedOrder(
        AdvancedOrder calldata advancedOrder,
        CriteriaResolver[] calldata criteriaResolvers,
        bytes32 fulfillerConduitKey,
        address recipient,
        uint256[] calldata newStatedPrices,
        uint256[] calldata newBondAmounts
    ) external payable returns (bool fulfilled) {
        // Validate and fulfill the order.
        if (advancedOrder.parameters.orderType != OrderType.FULL_RESTRICTED)
            revert NotRestrictedFullOrder();

        // verify consideration and offer
        uint256[] memory offerTokenIds;
        uint256 totalPrice;
        uint256 totalBond;
        (offerTokenIds, totalPrice, totalBond) = _verifyOffer(
            advancedOrder.parameters.offer,
            recipient
        );
        uint256 bondPayedToPaco = _verifyConsideration(
            advancedOrder.parameters.consideration,
            advancedOrder.parameters.offerer,
            totalPrice,
            totalBond
        );

        // fulfill order and swap assets
        for (uint256 i = 0; i < offerTokenIds.length; i++) {
            authorizedForTransfer[offerTokenIds[i]] = true;
        }
        SeaportInterface seaport = SeaportInterface(seaportAddress);
        if (
            !seaport.fulfillAdvancedOrder(
                advancedOrder,
                criteriaResolvers,
                fulfillerConduitKey,
                recipient
            )
        ) revert SeaportSwapFailed();

        // update bondInfo for each token transferred
        uint256 totalbond = 0;
        for (uint256 i = 0; i < offerTokenIds.length; i++) {
            totalbond += newBondAmounts[i];
            _postBond(
                recipient,
                offerTokenIds[i],
                newStatedPrices[i],
                newBondAmounts[i]
            );
            authorizedForTransfer[offerTokenIds[i]] = false;
        }
        if (bondPayedToPaco != totalBond) revert InvalidBondAmount();

        return true;
    }

    function _verifyOffer(OfferItem[] memory offer, address caller)
        internal
        view
        returns (
            uint256[] memory offerTokenIds,
            uint256 totalPrice,
            uint256 totalBond
        )
    {
        for (uint256 i = 0; i < offer.length; i++) {
            OfferItem memory offerItem = offer[i];
            if (offerItem.token != address(this)) continue;
            if (ownerOf(offerItem.identifierOrCriteria) == caller)
                revert FufillerSameAsTokenOwner();

            uint256 price;
            uint256 bond;
            uint256 fees;
            (price, bond, fees) = _getPriceBondFees(
                offerItem.identifierOrCriteria
            );

            offerTokenIds[offerTokenIds.length] = offerItem
                .identifierOrCriteria;

            totalPrice += price;
            totalBond += bond;
        }
    }

    function _verifyConsideration(
        ConsiderationItem[] memory consideration,
        address tokenOwner,
        uint256 expectedPricePaid,
        uint256 expectedBondPaid
    ) internal view returns (uint256) {
        uint256 paidToOwner;
        uint256 bondPayment;

        for (uint256 i = 0; i < consideration.length; i++) {
            ConsiderationItem memory considerationItem = consideration[i];
            if (considerationItem.startAmount != considerationItem.endAmount)
                revert NonStaticAmount();

            if (
                considerationItem.recipient == address(this) &&
                considerationItem.token == address(bondToken)
            ) {
                bondPayment = considerationItem.endAmount;
            } else if (
                considerationItem.recipient == tokenOwner &&
                considerationItem.token == address(bondToken)
            ) {
                paidToOwner += considerationItem.endAmount;
            }
        }
        if (paidToOwner < expectedPricePaid) revert InsufficientOwnerPayment();
        if (bondPayment < expectedBondPaid) revert InsufficientZonePayment();

        return bondPayment;
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
