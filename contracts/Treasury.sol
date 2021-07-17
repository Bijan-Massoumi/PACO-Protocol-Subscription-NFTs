// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./InterestUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface SphinxContract {
    function authorizedTreasuryMint(
        address recipient,
        uint256 initialStatedPrice,
        uint256 initialBond
    ) external;

    function authorizedTreasuryBurn(uint256 tokenId) external;

    function ownerOf(uint256 tokenId) external returns (address);
}

contract Treasury is Initializable, Ownable {
    SphinxContract sphinxContract;
    IERC20 erc20ToUse;
    uint256 burnRate;
    uint256 mintRate;

    function initialize(
        address sphinxAddress,
        address currencyContract,
        uint256 initialBurnRate,
        uint256 initialMintRate
    ) public initializer {
        sphinxContract = SphinxContract(sphinxAddress);
        erc20ToUse = IERC20(currencyContract);
        burnRate = initialBurnRate;
        mintRate = initialMintRate;
    }

    function setBurnRate(uint256 newBurnRate) external onlyOwner {
        burnRate = newBurnRate;
    }

    function setMintRate(uint256 newMintRate) external onlyOwner {
        mintRate = newMintRate;
    }

    function burnForRefund(uint256 tokenId) external {
        require(sphinxContract.ownerOf(tokenId) == msg.sender);
        erc20ToUse.transferFrom(
            address(this),
            msg.sender,
            (erc20ToUse.balanceOf(address(this)) * burnRate) / 10000
        );
        sphinxContract.authorizedTreasuryBurn(tokenId);
    }

    function mintForFee(uint256 initialStatedPrice, uint256 initialBond)
        external
    {
        erc20ToUse.transferFrom(
            msg.sender,
            address(this),
            (erc20ToUse.balanceOf(address(this)) * mintRate) / 10000
        );
        sphinxContract.authorizedTreasuryMint(
            msg.sender,
            initialStatedPrice,
            initialBond
        );
    }
}
