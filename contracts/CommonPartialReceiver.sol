// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title CommonPartialToken receiver interface
 * @dev Interface for any contract that wants to support safeTokenBuys
 * from Common Partial asset contracts.
 */
interface CommonPartialReceiver {
    /**
     * @dev Whenever an {CommonPartialToken} `tokenId` token is transferred to this contract via {safeBuyToken}
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the buy will be reverted.
     *
     * The selector can be obtained in Solidity with `onERC721Received.selector`.
     */
    function onCommonPartialTokenReceived(
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
