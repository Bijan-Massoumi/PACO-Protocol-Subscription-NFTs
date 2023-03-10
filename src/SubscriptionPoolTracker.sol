// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./SafUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ISubscriptionPoolTrackerErrors.sol";

struct SubscriptionPoolInfo {
    uint256 statedPrice;
    uint256 subscriptionPoolRemaining;
    uint256 lastModifiedAt;
    uint256 liquidationStartedAt;
}

struct FeeChangeTimestamp {
    uint256 timestamp;
    uint256 previousRate;
}

abstract contract SubscriptionPoolTracker is ISubscriptionPoolTrackerErrors {
    mapping(uint256 => SubscriptionPoolInfo)
        internal _subscriptionPoolInfosAtLastCheckpoint;
    FeeChangeTimestamp[] feeChangeTimestamps;

    // min percentage (10%) of total stated price that
    // must be convered by subscriptionPool
    uint256 internal minimumPoolRatio = 1000;
    //set by constructor
    uint256 internal subscriptionRate;
    // 100% fee rate
    uint256 internal maxSubscriptionRate = 10000;

    constructor(uint256 _subscriptionRate) {
        subscriptionRate = _subscriptionRate;
    }

    function getLiquidationStartedAt(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        uint256 liquidationStartedAt;
        SubscriptionPoolInfo
            memory currentOwnersSubscriptionPool = _subscriptionPoolInfosAtLastCheckpoint[
                tokenId
            ];
        (, , liquidationStartedAt) = _getCurrentSubscriptionPoolInfoForToken(
            currentOwnersSubscriptionPool
        );
        return liquidationStartedAt;
    }

    function _setSubscriptionRate(uint256 newsubscriptionRate) internal {
        if (newsubscriptionRate > maxSubscriptionRate) {
            revert InvalidAssessmentFee();
        }

        feeChangeTimestamps.push(
            FeeChangeTimestamp({
                timestamp: block.timestamp,
                previousRate: subscriptionRate
            })
        );
        subscriptionRate = newsubscriptionRate;
    }

    function _setMinimumSubscriptionPool(uint256 newMinimumPoolRatio) internal {
        minimumPoolRatio = newMinimumPoolRatio;
    }

    function _getCurrentSubscriptionPoolInfoForToken(
        SubscriptionPoolInfo memory lastSubscriptionPoolInfo
    )
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
            lastSubscriptionPoolInfo.subscriptionPoolRemaining == 0 ||
            lastSubscriptionPoolInfo.liquidationStartedAt != 0
        ) {
            return (0, 0, lastSubscriptionPoolInfo.liquidationStartedAt);
        }

        uint256 feesToReap;
        uint256 liquidationStartedAt;
        (feesToReap, liquidationStartedAt) = _calculateFeesAndLiquidationTime(
            lastSubscriptionPoolInfo.statedPrice,
            lastSubscriptionPoolInfo.lastModifiedAt,
            lastSubscriptionPoolInfo.subscriptionPoolRemaining
        );

        if (feesToReap > lastSubscriptionPoolInfo.subscriptionPoolRemaining) {
            return (
                0,
                feesToReap - lastSubscriptionPoolInfo.subscriptionPoolRemaining,
                liquidationStartedAt
            );
        }
        return (
            lastSubscriptionPoolInfo.subscriptionPoolRemaining - feesToReap,
            feesToReap,
            lastSubscriptionPoolInfo.liquidationStartedAt
        );
    }

    /*
     * @notice Calculates the fees that have accrued since the last checkpoint
     * and the time at which the subscriptionPool ran out (i.e. liquidation began)
     * @param statedPrice The price at which the subscriptionPool was last modified
     * @param lastModifiedAt The time at which the subscriptionPool/statedPrice was last modified
     * @param subscriptionPoolRemaining The amount of subscriptionPool remaining
     * @return totalFee The total fees that have accrued since the last checkpoint
     * @return liquidationTime The time at which the subscriptionPool hit 0
     */
    function _calculateFeesAndLiquidationTime(
        uint256 statedPrice,
        uint256 lastModifiedAt,
        uint256 subscriptionPoolRemaining
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
                // if the total fee is greater than the subscriptionPool remaining, we know that the subscriptionPool ran out
                if (totalFee > subscriptionPoolRemaining) {
                    liquidationTime = SafUtils._getTimeLiquidationBegan(
                        statedPrice,
                        startTime,
                        previousRate,
                        subscriptionPoolRemaining - prevIntervalFee
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
            subscriptionRate
        );
        if (totalFee > subscriptionPoolRemaining) {
            liquidationTime = SafUtils._getTimeLiquidationBegan(
                statedPrice,
                startTime,
                subscriptionRate,
                subscriptionPoolRemaining - prevIntervalFee
            );
        }

        return (totalFee, liquidationTime);
    }

    function _modifySubscriptionPoolInfo(
        SubscriptionPoolInfo storage _subscriptionPoolInfoAtLastCheckpoint,
        int256 subscriptionPoolDelta,
        int256 statedPriceDelta
    ) internal returns (uint256 feesToReap) {
        uint256 subscriptionPoolRemaining;
        uint256 liquidationStartedAt;
        (
            subscriptionPoolRemaining,
            feesToReap,
            liquidationStartedAt
        ) = _getCurrentSubscriptionPoolInfoForToken(
            _subscriptionPoolInfoAtLastCheckpoint
        );

        int256 newSubscriptionPool = int256(subscriptionPoolRemaining) +
            subscriptionPoolDelta;
        int256 newStatedPrice = int256(
            _subscriptionPoolInfoAtLastCheckpoint.statedPrice
        ) + statedPriceDelta;

        if (newStatedPrice < 0) revert InvalidAlterPriceValue();
        if (newSubscriptionPool < 0) revert InvalidAlterSubscriptionPoolValue();

        _persistNewSubscriptionPoolInfo(
            _subscriptionPoolInfoAtLastCheckpoint,
            uint256(newStatedPrice),
            uint256(newSubscriptionPool)
        );
    }

    function _persistNewSubscriptionPoolInfo(
        SubscriptionPoolInfo storage subscriptionPoolInfoRef,
        uint256 newStatedPrice,
        uint256 newSubscriptionPoolAmount
    ) internal {
        if (
            newSubscriptionPoolAmount <
            (newStatedPrice * minimumPoolRatio) / 10000
        ) revert InsufficientSubscriptionPool();

        subscriptionPoolInfoRef.statedPrice = newStatedPrice;
        subscriptionPoolInfoRef
            .subscriptionPoolRemaining = newSubscriptionPoolAmount;
        subscriptionPoolInfoRef.lastModifiedAt = block.timestamp;
        subscriptionPoolInfoRef.liquidationStartedAt = 0;
    }
}
