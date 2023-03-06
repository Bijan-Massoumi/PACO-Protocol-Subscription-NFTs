// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @title Custom errors for SneakyAuction
interface ISeaportErrors {
    error SeaportSwapFailed();
    error NonPacoToken();
    error NonBondToken();
    error FufillerSameAsTokenOwner();
    error NonStaticAmount();
    error InsufficientOwnerPayment();
    error InsufficientZonePayment();
    error NonExactBondAmount();
    error InvalidOwner();
}
