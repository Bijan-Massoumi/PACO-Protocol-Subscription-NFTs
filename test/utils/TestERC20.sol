// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

contract TestToken is ERC20 {
    constructor(string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {}

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        console.log(spender, from, to, allowance(from, spender));
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }
}
