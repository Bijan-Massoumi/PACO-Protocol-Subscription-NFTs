// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InterestUtils.sol";

struct BondInfo {
    uint256 bondRemaining;
    uint256 lastModifiedAt;
    uint256 liquidationStartedAt;
}

contract BondTracker {
    mapping(uint256 => uint256) internal _tokenIdToStatedPrice;
    mapping(address => BondInfo) internal _bondAtLastCheckpoint;

    modifier isNotBeingLiquidated(address owner) {
        require(
            _bondAtLastCheckpoint[owner].liquidationStartedAt == 0,
            "CommonPartialToken: cannot mint a token while being liquidated"
        );
        _;
    }

    // min percentage (10%) of total stated price that
    // must be convered by bond
    uint16 internal minimumBond = 100;

    uint16 interestRate = 200;

    function _getCurrentBondInfoForAddress(
        BondInfo memory lastBondInfo,
        uint256 statedPriceSum
    )
        internal
        view
        returns (
            uint256 remainingBond,
            uint256 interestToReap,
            uint256 liquidationStartedAt
        )
    {
        BondInfo memory bondInfoForAddress = _bondAtLastCheckpoint[owner];

        // either they have no tokens or they are being liquidated
        if (
            bondInfoForAddress.bondRemaining == 0 ||
            bondInfoForAddress.liquidationStartedAt == 0
        ) {
            return (0, 0, bondInfoForAddress.liquidationStartedAt, );
        }
        uint256 totalInterest = InterestUtils
        ._calculateInterestSinceLastCheckIn(
            statedPriceSum,
            bondInfoForAddress.lastModifiedAt,
            interestRate
        );
        if (interestToReap > bondInfoForAddress.bondRemaining) {
            return (
                0,
                totalInterest - bondInfoForAddress.bondRemaining,
                InterestUtils._getTimeLiquidationBegan(
                    statedPriceSum,
                    bondInfoForAddress.lastModifiedAt,
                    interestRate,
                    bondInfoForAddress.bondRemaining
                )
            );
        } else {
            return (
                bondInfoForAddress.bondRemaining - totalInterest,
                totalInterest,
                bondInfoForAddress.liquidationStartedAt,

            );
        }
    }

    function _reapInterestAndUpdateBond(address owner, uint256 statedPriceSum)
        internal
        returns (
            uint256 remainingBond,
            uint256 interestToReap,
            uint256 liquidationStartedAt
        )
    {
        BondInfo storage bondInfo = _bondAtLastCheckpoint[owner];

        (
            remainingBond,
            interestToReap,
            liquidationStartedAt,

        ) = _getCurrentBondInfoForAddress(bondInfo, statedPriceSum);

        bondInfo.bondRemaining = remainingBond;
        bondInfo.interestToReap = interestToReap;
        bondInfo.liquidationStartedAt = liquidationStartedAt;
    }
}
