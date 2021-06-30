// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";

library InterestUtils {
    function _calculateInterestSinceLastCheckIn(
        uint256 totalStatedPrice,
        uint256 lastCheckInAt,
        uint16 interestRate
    ) internal view returns (uint256 interestToReap) {
        interestToReap =
            (interestRate *
                totalStatedPrice *
                (block.timestamp - lastCheckInAt)) /
            (31536000 * 10000);
    }

    function _getTimeLiquidationBegan(
        uint256 totalStatedPrice,
        uint256 lastCheckInAt,
        uint16 interestRate,
        uint256 bondRemaining
    ) internal pure returns (uint256 liquidationStartedAt) {
        liquidationStartedAt =
            ((bondRemaining * (31536000 * 10000)) +
                (interestRate * totalStatedPrice * lastCheckInAt)) /
            (interestRate * totalStatedPrice);
    }
}
