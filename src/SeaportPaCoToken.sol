// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./PaCoToken.sol";
import "./ZoneInterface.sol";
import {ConsiderationItem, OfferItem, OrderType} from "./SeaportStructs.sol";

abstract contract SeaportPaCoToken is PaCoToken, ZoneInterface {
    // only supports seaport 1.1
    address seaportAddress;
    // tokenID to authroized bool
    mapping(uint256 => bool) internal authorizedForTransfer;

    // Errors --------------------------------------------

    error NonSeaportCaller();
    error NotRestrictedFullOrder();
    error FufillerSameAsTokenOwner();
    error NonStaticAmount();
    error InsufficientOwnerPayment();
    error InsufficientZonePayment();
    error NonBondToken();

    constructor(
        address tokenAddress,
        address withdrawAddress,
        uint16 selfAssessmentRate,
        address _seaportAddress
    ) PaCoToken(tokenAddress, withdrawAddress, selfAssessmentRate) {
        seaportAddress = _seaportAddress;
    }

    function isValidOrder(
        bytes32 orderHash,
        address caller,
        address offerer,
        bytes32 zoneHash
    ) external pure returns (bytes4 validOrderMagicValue) {
        orderHash;
        caller;
        offerer;
        zoneHash;
        return bytes4(0xffffffff);
    }

    function isValidOrderIncludingExtraData(
        bytes32 orderHash,
        address caller,
        AdvancedOrder calldata order,
        bytes32[] calldata priorOrderHashes,
        CriteriaResolver[] calldata criteriaResolvers
    ) external view returns (bytes4 validOrderMagicValue) {
        criteriaResolvers;
        priorOrderHashes;
        if (_msgSender() != seaportAddress) revert NonSeaportCaller();
        if (order.parameters.orderType != OrderType.FULL_RESTRICTED)
            revert NotRestrictedFullOrder();

        uint256[] memory tokenIdsTransferred;
        uint256 totalPrice;
        uint256 totalBond;
        (tokenIdsTransferred, totalPrice, totalBond) = _verifyOffer(
            order.parameters.offer,
            caller
        );

        uint256 bondPayment = _verifyConsideration(
            order.parameters.consideration,
            order.parameters.offerer,
            totalPrice,
            totalBond
        );

        validOrderMagicValue = ZoneInterface.isValidOrder.selector;
    }

    function _verifyOffer(OfferItem[] memory offer, address caller)
        internal
        view
        returns (
            uint256[] memory tokenIdsTransferred,
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

            tokenIdsTransferred[tokenIdsTransferred.length] = offerItem
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
