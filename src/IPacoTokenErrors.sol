// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @title Custom errors for SneakyAuction
interface IPacoTokenErrors {
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
}
