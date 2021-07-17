// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract TreasuryOwnable is Ownable {
    address internal _treasury;
    event OwnershipClubTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor(address treasuryAddress) {
        _treasury = treasuryAddress;
    }

    /**
     * @dev Returns the address of the club/treasury.
     */
    function clubAddress() public view virtual returns (address) {
        return _treasury;
    }

    /**
     * @dev Throws if called by any account other than the membershipClub.
     */
    modifier onlyTreasury() {
        require(
            clubAddress() == _msgSender(),
            "Ownable: caller is not the owner"
        );
        _;
    }

    modifier anyOwner() {
        require(
            clubAddress() == _msgSender() || owner() == _msgSender(),
            "OwnershipManager: caller isnt membershipContract or Owner"
        );
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current anyOwner.
     */
    function transferClubOwnership(address newOwner) public virtual anyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipClubTransferred(_treasury, newOwner);
        _treasury = newOwner;
    }
}
