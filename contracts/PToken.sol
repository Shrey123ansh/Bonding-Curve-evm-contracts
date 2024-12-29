// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PToken is ERC20 {
    constructor(address initialOwner)
        ERC20("PToken", "PTM")
    {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
