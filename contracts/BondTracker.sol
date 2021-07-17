// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InterestUtils.sol";
import "./OwnershipManager.sol";

struct BondInfo {
    uint256 statedPrice;
    uint256 bondRemaining;
    uint256 lastModifiedAt;
    uint256 liquidationStartedAt;
}

contract BondTracker is TreasuryOwnable {
    mapping(uint256 => BondInfo) internal _bondInfosAtLastCheckpoint;
    mapping(address => uint256) internal _bondToBeReturnedToAddress;

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

        require(
            vettedNewBond > (vettedStatedPrice * minimumBond) / 10000,
            "Cannot update price or bond unless > 10% of statedPrice is posted in bond."
        );

        _bondInfoAtLastCheckpoint.statedPrice = vettedStatedPrice;
        _bondInfoAtLastCheckpoint.bondRemaining = vettedNewBond;
        _bondInfoAtLastCheckpoint.lastModifiedAt = block.timestamp;
        _bondInfoAtLastCheckpoint.liquidationStartedAt = 0;

        amountToTransfer = _bondDelta > 0 ? uint256(_bondDelta) : 0;
    }

    function _generateAndPersistNewBondInfo(
        uint256 tokenId,
        uint256 initialStatedPrice,
        uint256 bondAmount
    ) internal {
        require(
            bondAmount > (initialStatedPrice * minimumBond) / 10000,
            "Cannot mint/purchase unless > 10% of statedPrice is posted in bond."
        );
        _bondInfosAtLastCheckpoint[tokenId] = BondInfo(
            initialStatedPrice,
            bondAmount,
            block.timestamp,
            0
        );
    }
}
