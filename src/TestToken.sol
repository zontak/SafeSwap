// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("SafeSwap Demo", "SSDEMO") {
        _mint(msg.sender, 1_000_000 * 1e18);
    }
}
