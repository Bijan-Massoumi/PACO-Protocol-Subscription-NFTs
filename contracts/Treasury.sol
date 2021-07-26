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

    function initialize(address sphinxAddress, address currencyContract)
        public
        initializer
    {
        sphinxContract = SphinxContract(sphinxAddress);
        erc20ToUse = IERC20(currencyContract);
    }

    function payToAddress(address recipient, uint256 amount)
        external
        onlyOwner
    {
        erc20ToUse.transferFrom(address(this), recipient, amount);
    }
}
