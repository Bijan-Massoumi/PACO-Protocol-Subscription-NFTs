// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    IERC20 erc20ToUse;

    constructor(address currencyContract)
    {
        erc20ToUse = IERC20(currencyContract);
    }

    function payToAddress(address recipient, uint256 amount)
        external
        onlyOwner
    {
        erc20ToUse.transferFrom(address(this), recipient, amount);
    }
}
