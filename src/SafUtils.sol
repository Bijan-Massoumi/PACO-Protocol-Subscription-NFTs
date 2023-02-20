// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

library SafUtils {
    function _calculateSafSinceLastCheckIn(
        uint256 totalStatedPrice,
        uint256 lastCheckInAt,
        uint16 feeRate
    ) internal view returns (uint256 feeToReap) {
        feeToReap =
            (feeRate * totalStatedPrice * (block.timestamp - lastCheckInAt)) /
            (31536000 * 10000);
    }

    function _getTimeLiquidationBegan(
        uint256 totalStatedPrice,
        uint256 lastCheckInAt,
        uint16 feeRate,
        uint256 bondRemaining
    ) internal pure returns (uint256 liquidationStartedAt) {
        liquidationStartedAt =
            (bondRemaining * (31536000 * 10000)) /
            (feeRate * totalStatedPrice) +
            lastCheckInAt;
    }

    function getLiquidationPrice(
        uint256 value,
        uint256 t,
        uint256 halfLife
    ) internal pure returns (uint256 price) {
        price = value >> (t / halfLife);
        t %= halfLife;
        price -= (price * t) / halfLife / 2;
    }
}
