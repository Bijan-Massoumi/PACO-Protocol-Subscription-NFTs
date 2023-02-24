// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./SafUtils.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

struct FeeChangeTimestamp {
    uint256 timestamp;
    uint256 previousRate;
}

abstract contract BondTracker is Ownable {
    mapping(uint256 => BondInfo) internal _bondInfosAtLastCheckpoint;
    FeeChangeTimestamp[] feeChangeTimestamps;
    mapping(address => mapping(uint256 => EscrowIntentToReceive)) escrowIntentToReceive;

    // min percentage (10%) of total stated price that
    // must be convered by bond
    uint256 internal minimumBond = 1000;
    //set by constructor
    uint256 internal selfAssessmentRate;

    /// ============ Errors ============
    /// @notice Thrown if invalid price values
    error InvalidAlterPriceValue();
    /// @notice Thrown if invalid bond values
    error InvalidAlterBondValue();
    /// @notice Thrown if bond isnt enough to cover miminum bond
    error InsufficientBond();

    constructor(uint256 _selfAssessmentRate) {
        selfAssessmentRate = _selfAssessmentRate;
    }

    function getLiquidationStartedAt(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        uint256 liquidationStartedAt;
        BondInfo memory currentOwnersBond = _bondInfosAtLastCheckpoint[tokenId];
        (, , liquidationStartedAt) = _getCurrentBondInfoForToken(
            currentOwnersBond
        );
        return liquidationStartedAt;
    }

    function setSelfAssessmentRate(uint16 newSelfAssessmentRate)
        external
        onlyOwner
    {
        feeChangeTimestamps.push(
            FeeChangeTimestamp({
                timestamp: block.timestamp,
                previousRate: selfAssessmentRate
            })
        );
        selfAssessmentRate = newSelfAssessmentRate;
    }

    function setMinimumBond(uint16 newMinimumBond) external onlyOwner {
        minimumBond = newMinimumBond;
    }

    function _getCurrentBondInfoForToken(BondInfo memory lastBondInfo)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // either they have no tokens or they are being liquidated
        if (
            lastBondInfo.bondRemaining == 0 ||
            lastBondInfo.liquidationStartedAt != 0
        ) {
            return (0, 0, lastBondInfo.liquidationStartedAt);
        }

        uint256 feesToReap;
        uint256 liquidationStartedAt;
        (feesToReap, liquidationStartedAt) = _calculateFeesAndLiquidationTime(
            lastBondInfo.statedPrice,
            lastBondInfo.lastModifiedAt,
            lastBondInfo.bondRemaining
        );

        if (feesToReap > lastBondInfo.bondRemaining) {
            return (
                0,
                feesToReap - lastBondInfo.bondRemaining,
                liquidationStartedAt
            );
        }
        return (
            lastBondInfo.bondRemaining - feesToReap,
            feesToReap,
            lastBondInfo.liquidationStartedAt
        );
    }

    /*
     * @notice Calculates the fees that have accrued since the last checkpoint
     * and the time at which the bond ran out (i.e. liquidation began)
     * @param statedPrice The price at which the bond was last modified
     * @param lastModifiedAt The time at which the bond/statedPrice was last modified
     * @param bondRemaining The amount of bond remaining
     * @return totalFee The total fees that have accrued since the last checkpoint
     * @return liquidationTime The time at which the bond hit 0
     */
    function _calculateFeesAndLiquidationTime(
        uint256 statedPrice,
        uint256 lastModifiedAt,
        uint256 bondRemaining
    ) internal view returns (uint256, uint256) {
        uint256 totalFee;
        uint256 prevIntervalFee;
        uint256 liquidationTime;
        uint256 startTime = lastModifiedAt;
        // iterate through all fee changes that have happened since the last checkpoint
        for (uint256 i = 0; i < feeChangeTimestamps.length; i++) {
            uint256 feeChangeTimestamp = feeChangeTimestamps[i].timestamp;
            uint256 previousRate = feeChangeTimestamps[i].previousRate;
            if (feeChangeTimestamp > startTime) {
                uint256 intervalFee = SafUtils._calculateSafBetweenTimes(
                    statedPrice,
                    startTime,
                    feeChangeTimestamp,
                    previousRate
                );
                totalFee += intervalFee;
                // if the total fee is greater than the bond remaining, we know that the bond ran out
                if (totalFee > bondRemaining) {
                    liquidationTime = SafUtils._getTimeLiquidationBegan(
                        statedPrice,
                        startTime,
                        previousRate,
                        bondRemaining - prevIntervalFee
                    );
                    return (totalFee, liquidationTime);
                }
                startTime = feeChangeTimestamp;
                prevIntervalFee += intervalFee;
            }
        }

        // calculate the fee for the current interval (i.e. since the last fee change)
        totalFee += SafUtils._calculateSafBetweenTimes(
            statedPrice,
            startTime,
            block.timestamp,
            selfAssessmentRate
        );
        if (totalFee > bondRemaining) {
            liquidationTime = SafUtils._getTimeLiquidationBegan(
                statedPrice,
                startTime,
                selfAssessmentRate,
                bondRemaining - prevIntervalFee
            );
        }

        return (totalFee, liquidationTime);
    }

    function _modifyBondInfo(
        BondInfo storage _bondInfoAtLastCheckpoint,
        int256 bondDelta,
        int256 statedPriceDelta
    ) internal returns (uint256 feesToReap) {
        uint256 bondRemaining;
        uint256 liquidationStartedAt;
        (
            bondRemaining,
            feesToReap,
            liquidationStartedAt
        ) = _getCurrentBondInfoForToken(_bondInfoAtLastCheckpoint);

        int256 newBond = int256(bondRemaining) + bondDelta;
        int256 newStatedPrice = int256(_bondInfoAtLastCheckpoint.statedPrice) +
            statedPriceDelta;

        if (newStatedPrice < 0) revert InvalidAlterPriceValue();
        if (newBond < 0) revert InvalidAlterBondValue();

        _persistNewBondInfo(
            _bondInfoAtLastCheckpoint,
            uint256(newStatedPrice),
            uint256(newBond)
        );
    }

    function _persistNewBondInfo(
        BondInfo storage bondInfoRef,
        uint256 newStatedPrice,
        uint256 newBondAmount
    ) internal {
        if (newBondAmount < (newStatedPrice * minimumBond) / 10000)
            revert InsufficientBond();

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
        require(expiry > block.timestamp);
        escrowIntentToReceive[msg.sender][tokenId] = EscrowIntentToReceive(
            price,
            bond,
            expiry
        );
    }
}
