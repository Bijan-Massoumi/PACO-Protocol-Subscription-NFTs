// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "./InterestUtils.sol";
import "./OwnershipManager.sol";

struct BondInfo {
    uint256 statedPrice;
    uint256 bondRemaining;
    uint256 lastModifiedAt;
    uint256 liquidationStartedAt;
}

struct EscrowIntentToReceive {
    uint256 statedPrice;
    uint256 bondToPost;
    uint256 expiry;
}

contract BondTracker is TreasuryOwnable {
    mapping(uint256 => BondInfo) internal _bondInfosAtLastCheckpoint;
    mapping(address => uint256) internal _bondToBeReturnedToAddress;
    mapping(address => mapping(uint256 => EscrowIntentToReceive)) escrowIntentToReceive;

    // min percentage (10%) of total stated price that
    // must be convered by bond
    uint16 internal minimumBond = 1000;
    //set by constructor
    uint16 internal interestRate;
    uint256 halfLife = 172800;

    constructor(address treasuryContract) TreasuryOwnable(treasuryContract) {}

    function _getCurrentBondInfoForToken(BondInfo memory lastBondInfo)
        internal
        view
        returns (
            uint256 bondRemaining,
            uint256 interestToReap,
            uint256 liquidationStartedAt
        )
    {
        // either they have no tokens or they are being liquidated
        if (
            lastBondInfo.bondRemaining == 0 ||
            lastBondInfo.liquidationStartedAt != 0
        ) {
            return (0, 0, lastBondInfo.liquidationStartedAt);
        }
        uint256 totalInterest = InterestUtils
        ._calculateInterestSinceLastCheckIn(
            lastBondInfo.statedPrice,
            lastBondInfo.lastModifiedAt,
            interestRate
        );

        if (totalInterest > lastBondInfo.bondRemaining) {
            return (
                0,
                totalInterest - lastBondInfo.bondRemaining,
                InterestUtils._getTimeLiquidationBegan(
                    lastBondInfo.statedPrice,
                    lastBondInfo.lastModifiedAt,
                    interestRate,
                    lastBondInfo.bondRemaining
                )
            );
        } else {
            return (
                lastBondInfo.bondRemaining - totalInterest,
                totalInterest,
                lastBondInfo.liquidationStartedAt
            );
        }
    }

    function setInterestRate(uint16 newInterestRate) external onlyOwner {
        interestRate = newInterestRate;
    }

    function setHalfLife(uint16 newHalfLife) external onlyOwner {
        halfLife = newHalfLife;
    }

    function setMinimumBond(uint16 newMinimumBond) external onlyOwner {
        minimumBond = newMinimumBond;
    }

    function _refreshAndModifyExistingBondInfo(
        BondInfo storage _bondInfoAtLastCheckpoint,
        int256 _bondDelta,
        int256 _statedPriceDelta
    ) internal returns (uint256 interestToReap, uint256 amountToTransfer) {
        uint256 bondRemaining;
        uint256 liquidationStartedAt;
        (
            bondRemaining,
            interestToReap,
            liquidationStartedAt
        ) = _getCurrentBondInfoForToken(_bondInfoAtLastCheckpoint);

        int256 newBond = int256(bondRemaining) + _bondDelta;
        int256 newStatedPrice = int256(_bondInfoAtLastCheckpoint.statedPrice) +
            _statedPriceDelta;

        require(
            newBond >= 0 && newStatedPrice >= 0,
            "bad values passed for delta values"
        );
        uint256 vettedNewBond = uint256(newBond);
        uint256 vettedStatedPrice = uint256(newStatedPrice);

        _persistNewBondInfo(
            _bondInfoAtLastCheckpoint,
            vettedStatedPrice,
            vettedNewBond
        );

        amountToTransfer = _bondDelta > 0 ? uint256(_bondDelta) : 0;
    }

    function _persistNewBondInfo(
        BondInfo storage bondInfoRef,
        uint256 newStatedPrice,
        uint256 newBondAmount
    ) internal {
        require(
            newBondAmount >= (newStatedPrice * minimumBond) / 10000,
            " > 10% of statedPrice must be posted in bond."
        );
        bondInfoRef.statedPrice = newStatedPrice;
        bondInfoRef.bondRemaining = newBondAmount;
        bondInfoRef.lastModifiedAt = block.timestamp;
        bondInfoRef.liquidationStartedAt = 0;
    }

    function _setEscrowIntent(
        uint256 tokenId,
        uint256 price,
        uint256 bond,
        uint256 expiry
    ) internal {
        escrowIntentToReceive[msg.sender][tokenId] = EscrowIntentToReceive(
            price,
            bond,
            expiry
        );
    }
}
