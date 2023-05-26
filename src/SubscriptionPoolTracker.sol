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
    event NewHalfLifeSet(uint256 newHalfLife);
    event FeeCollected(
        uint256 tokenId,
        uint256 feeCollected,
        uint256 subscriptionPoolRemaining,
        uint256 liquidationStartedAt
    );

    mapping(uint256 => SubscriptionPoolInfo)
        internal _subscriptionPoolInfosAtLastCheckpoint;

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
            _subscriptionPoolInfosAtLastCheckpoint[tokenId]
        );
        return subscriptionPoolRemaining;
    }

    function _getPrice(uint256 tokenId) internal view returns (uint256) {
        uint256 liquidationStartedAt;
        SubscriptionPoolInfo
            memory subscriptionPoolInfo = _subscriptionPoolInfosAtLastCheckpoint[
                tokenId
            ];
        (, , liquidationStartedAt) = _getCurrentSubscriptionPoolInfoForToken(
            subscriptionPoolInfo
        );
        if (liquidationStartedAt != 0) {
            return
                _getLiquidationPrice(
                    subscriptionPoolInfo.statedPrice,
                    liquidationStartedAt
                );
        } else {
            return subscriptionPoolInfo.statedPrice;
        }
    }

    function _getStatedPrice(uint256 tokenId) internal view returns (uint256) {
        return _subscriptionPoolInfosAtLastCheckpoint[tokenId].statedPrice;
    }

    function _getLiquidationStartedAt(
        uint256 tokenId
    ) internal view returns (uint256) {
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

    function _getFeesToCollectForToken(
        uint256 tokenId
    ) internal returns (uint256) {
        uint256 feeCollected;
        uint256 subscriptionPoolRemaining;
        uint256 liquidationStartedAt;
        SubscriptionPoolInfo
            memory currSubscriptionPoolInfo = _subscriptionPoolInfosAtLastCheckpoint[
                tokenId
            ];

        (
            subscriptionPoolRemaining,
            feeCollected,
            liquidationStartedAt
        ) = _getCurrentSubscriptionPoolInfoForToken(currSubscriptionPoolInfo);

        _persistNewSubscriptionPoolInfo(
            tokenId,
            currSubscriptionPoolInfo.statedPrice,
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
        SubscriptionPoolInfo memory lastSubscriptionPoolInfo
    ) internal view returns (uint256, uint256, uint256) {
        // either they have no tokens or they are being liquidated
        if (
            lastSubscriptionPoolInfo.subscriptionPoolRemaining == 0 ||
            lastSubscriptionPoolInfo.liquidationStartedAt != 0
        ) {
            return (0, 0, lastSubscriptionPoolInfo.liquidationStartedAt);
        }

        uint256 feesToCollect;
        uint256 liquidationStartedAt;
        (
            feesToCollect,
            liquidationStartedAt
        ) = _calculateFeesAndLiquidationTime(
            lastSubscriptionPoolInfo.statedPrice,
            lastSubscriptionPoolInfo.lastModifiedAt,
            lastSubscriptionPoolInfo.subscriptionPoolRemaining
        );

        if (
            feesToCollect > lastSubscriptionPoolInfo.subscriptionPoolRemaining
        ) {
            return (
                0,
                lastSubscriptionPoolInfo.subscriptionPoolRemaining,
                liquidationStartedAt
            );
        }
        return (
            lastSubscriptionPoolInfo.subscriptionPoolRemaining - feesToCollect,
            feesToCollect,
            lastSubscriptionPoolInfo.liquidationStartedAt
        );
    }

    function _getPriceSubscriptionPoolFees(
        uint256 tokenId
    ) internal view virtual returns (uint256, uint256, uint256) {
        SubscriptionPoolInfo
            memory currentOwnersSubscriptionPool = _subscriptionPoolInfosAtLastCheckpoint[
                tokenId
            ];
        uint256 price = currentOwnersSubscriptionPool.statedPrice;
        uint256 feesToCollect;
        uint256 liquidationStartedAt;
        uint256 subscriptionPoolRemaining;
        (
            subscriptionPoolRemaining,
            feesToCollect,
            liquidationStartedAt
        ) = _getCurrentSubscriptionPoolInfoForToken(
            currentOwnersSubscriptionPool
        );

        if (liquidationStartedAt != 0) {
            price = _getLiquidationPrice(
                currentOwnersSubscriptionPool.statedPrice,
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
        SubscriptionPoolInfo
            storage subPoolInfo = _subscriptionPoolInfosAtLastCheckpoint[
                tokenId
            ];
        uint256 subscriptionPoolRemaining;
        (
            subscriptionPoolRemaining,
            feesToCollect,

        ) = _getCurrentSubscriptionPoolInfoForToken(subPoolInfo);

        //  apply deltas to existing pool / price
        int256 subPool = int256(subscriptionPoolRemaining) +
            subscriptionPoolDelta;
        int256 statedPrice = int256(subPoolInfo.statedPrice) + statedPriceDelta;
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

        SubscriptionPoolInfo
            storage subscriptionPoolInfo = _subscriptionPoolInfosAtLastCheckpoint[
                tokenId
            ];

        if (subscriptionPoolInfo.statedPrice != newStatedPrice) {
            subscriptionPoolInfo.statedPrice = newStatedPrice;
        }

        if (
            subscriptionPoolInfo.subscriptionPoolRemaining !=
            newSubscriptionPoolAmount
        ) {
            subscriptionPoolInfo
                .subscriptionPoolRemaining = newSubscriptionPoolAmount;
        }

        if (
            subscriptionPoolInfo.liquidationStartedAt != newLiquidationStartedAt
        ) {
            subscriptionPoolInfo.liquidationStartedAt = newLiquidationStartedAt;
        }
        subscriptionPoolInfo.lastModifiedAt = block.timestamp;
    }
}
