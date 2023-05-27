// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./SafUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ISubscriptionPoolTrackerErrors.sol";

struct SubscriptionPoolCheckpoint {
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
    event NewHalfLifeSet(uint256 newHalfLife);
    event FeeCollected(
        uint256 tokenId,
        uint256 feeCollected,
        uint256 subscriptionPoolRemaining,
        uint256 liquidationStartedAt
    );

    mapping(uint256 => SubscriptionPoolCheckpoint)
        internal _subscriptionCheckpoints;

    uint256 internal subscriptionRate;
    FeeChangeTimestamp[] feeChangeTimestamps;
    //  If the token is being liquidated, the stated price will halve every halfLife period of time
    uint256 halfLife;

    // min percentage (10%) of total stated price that
    // must be convered by subscriptionPool
    uint256 internal minimumPoolRatio = 1000;
    // 100% fee rate
    uint256 internal maxSubscriptionRate = 10000;
    // 100% pool percent
    uint256 internal maxMinimumPoolRatio = 10000;

    constructor(uint256 _halfLife, uint256 _subscriptionRate) {
        halfLife = _halfLife;
        subscriptionRate = _subscriptionRate;
    }

    function _setHalfLife(uint256 newHalfLife) internal {
        halfLife = newHalfLife;
        emit NewHalfLifeSet(newHalfLife);
    }

    function _setSubscriptionRate(uint256 newSubscriptionRate) internal {
        feeChangeTimestamps.push(
            FeeChangeTimestamp({
                timestamp: block.timestamp,
                previousRate: subscriptionRate
            })
        );
        subscriptionRate = newSubscriptionRate;
    }

    function _setMinimumPoolRatio(uint256 newMinimumPoolRatio) internal {
        minimumPoolRatio = newMinimumPoolRatio;
    }

    function _getLiquidationPrice(
        uint statedPrice,
        uint256 liquidationStartedAt
    ) internal view returns (uint256) {
        return
            SafUtils.getLiquidationPrice(
                statedPrice,
                block.timestamp - liquidationStartedAt,
                halfLife
            );
    }

    function _getSubscriptionPoolRemaining(
        uint256 tokenId
    ) internal view returns (uint256) {
        uint256 subscriptionPoolRemaining;
        (
            subscriptionPoolRemaining,
            ,

        ) = _getCurrentSubscriptionPoolInfoForToken(
            _subscriptionCheckpoints[tokenId]
        );
        return subscriptionPoolRemaining;
    }

    function _getPrice(uint256 tokenId) internal view returns (uint256) {
        uint256 liquidationStartedAt;
        SubscriptionPoolCheckpoint
            memory checkpoint = _subscriptionCheckpoints[
                tokenId
            ];
        (, , liquidationStartedAt) = _getCurrentSubscriptionPoolInfoForToken(
            checkpoint
        );
        if (liquidationStartedAt != 0) {
            return
                _getLiquidationPrice(
                    checkpoint.statedPrice,
                    liquidationStartedAt
                );
        } else {
            return checkpoint.statedPrice;
        }
    }

    function _getStatedPrice(uint256 tokenId) internal view returns (uint256) {
        return _subscriptionCheckpoints[tokenId].statedPrice;
    }

    function _getLiquidationStartedAt(
        uint256 tokenId
    ) internal view returns (uint256) {
        uint256 liquidationStartedAt;
        SubscriptionPoolCheckpoint
            memory checkpoint = _subscriptionCheckpoints[
                tokenId
            ];
        (, , liquidationStartedAt) = _getCurrentSubscriptionPoolInfoForToken(
            checkpoint
        );
        return liquidationStartedAt;
    }

    function _getFeesToCollectForToken(
        uint256 tokenId
    ) internal returns (uint256) {
        uint256 feeCollected;
        uint256 subscriptionPoolRemaining;
        uint256 liquidationStartedAt;
        SubscriptionPoolCheckpoint
            memory checkpoint = _subscriptionCheckpoints[
                tokenId
            ];

        (
            subscriptionPoolRemaining,
            feeCollected,
            liquidationStartedAt
        ) = _getCurrentSubscriptionPoolInfoForToken(checkpoint);

        _persistNewSubscriptionPoolInfo(
            tokenId,
            checkpoint.statedPrice,
            subscriptionPoolRemaining,
            liquidationStartedAt
        );

        emit FeeCollected(
            tokenId,
            feeCollected,
            subscriptionPoolRemaining,
            liquidationStartedAt
        );

        return feeCollected;
    }

    function _getCurrentSubscriptionPoolInfoForToken(
        SubscriptionPoolCheckpoint memory subscriptionCheckpoint
    ) internal view returns (uint256, uint256, uint256) {
        // either they have no tokens or they are being liquidated
        if (
            subscriptionCheckpoint.subscriptionPoolRemaining == 0 ||
            subscriptionCheckpoint.liquidationStartedAt != 0
        ) {
            return (0, 0, subscriptionCheckpoint.liquidationStartedAt);
        }

        uint256 feesToCollect;
        uint256 liquidationStartedAt;
        (
            feesToCollect,
            liquidationStartedAt
        ) = _calculateFeesAndLiquidationTime(
            subscriptionCheckpoint.statedPrice,
            subscriptionCheckpoint.lastModifiedAt,
            subscriptionCheckpoint.subscriptionPoolRemaining
        );

        return (
            subscriptionCheckpoint.subscriptionPoolRemaining - feesToCollect,
            feesToCollect,
            liquidationStartedAt
        );
    }

    function _getPriceSubscriptionPoolFees(
        uint256 tokenId
    ) internal view virtual returns (uint256, uint256, uint256) {
        SubscriptionPoolCheckpoint
            memory checkpoint = _subscriptionCheckpoints[
                tokenId
            ];
        uint256 price = checkpoint.statedPrice;
        uint256 feesToCollect;
        uint256 liquidationStartedAt;
        uint256 subscriptionPoolRemaining;
        (
            subscriptionPoolRemaining,
            feesToCollect,
            liquidationStartedAt
        ) = _getCurrentSubscriptionPoolInfoForToken(
            checkpoint
        );

        if (liquidationStartedAt != 0) {
            price = _getLiquidationPrice(
                checkpoint.statedPrice,
                liquidationStartedAt
            );
        }

        return (price, subscriptionPoolRemaining, feesToCollect);
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
                    return (
                        subscriptionPoolRemaining,
                        SafUtils._getTimeLiquidationBegan(
                            statedPrice,
                            startTime,
                            previousRate,
                            subscriptionPoolRemaining - prevIntervalFee
                        )
                    );
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
            return (
                subscriptionPoolRemaining,
                SafUtils._getTimeLiquidationBegan(
                    statedPrice,
                    startTime,
                    subscriptionRate,
                    subscriptionPoolRemaining - prevIntervalFee
                )
            );
        }

        return (totalFee, 0);
    }

    function _updateStatedPriceAndSubPool(
        uint256 tokenId,
        int256 subscriptionPoolDelta,
        int256 statedPriceDelta
    )
        internal
        returns (
            uint256 feesToCollect,
            uint256 newStatedPrice,
            uint256 newSubscriptionPool
        )
    {
        SubscriptionPoolCheckpoint
            storage checkpoint = _subscriptionCheckpoints[
                tokenId
            ];
        uint256 subscriptionPoolRemaining;
        (
            subscriptionPoolRemaining,
            feesToCollect,

        ) = _getCurrentSubscriptionPoolInfoForToken(checkpoint);

        //  apply deltas to existing pool / price
        int256 subPool = int256(subscriptionPoolRemaining) +
            subscriptionPoolDelta;
        int256 statedPrice = int256(checkpoint.statedPrice) + statedPriceDelta;
        if (statedPrice < 0) revert InvalidAlterPriceValue();
        if (subPool < 0) revert InvalidAlterSubscriptionPoolValue();

        newStatedPrice = uint256(statedPrice);
        newSubscriptionPool = uint256(subPool);
        _persistNewSubscriptionPoolInfo(
            tokenId,
            newStatedPrice,
            newSubscriptionPool,
            0
        );
    }

    function _persistNewSubscriptionPoolInfo(
        uint256 tokenId,
        uint256 newStatedPrice,
        uint256 newSubscriptionPoolAmount,
        uint256 newLiquidationStartedAt
    ) internal {
        if (
            newSubscriptionPoolAmount <
            (newStatedPrice * minimumPoolRatio) / 10000
        ) revert InsufficientSubscriptionPool();

        SubscriptionPoolCheckpoint
            storage checkpoint = _subscriptionCheckpoints[
                tokenId
            ];

        if (checkpoint.statedPrice != newStatedPrice) {
            checkpoint.statedPrice = newStatedPrice;
        }

        if (
            checkpoint.subscriptionPoolRemaining !=
            newSubscriptionPoolAmount
        ) {
            checkpoint
                .subscriptionPoolRemaining = newSubscriptionPoolAmount;
        }

        if (
            checkpoint.liquidationStartedAt != newLiquidationStartedAt
        ) {
            checkpoint.liquidationStartedAt = newLiquidationStartedAt;
        }
        checkpoint.lastModifiedAt = block.timestamp;
    }
}
