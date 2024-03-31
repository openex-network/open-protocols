// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OEXToken is ERC20 {
    constructor() ERC20("OpenEX Network Token", "OEX") {
        uint256 initialSupply = 10_000_000_000 ether;

        // 10% : Community Airdrop Pool Part 1 - Satoshi App
        // 10% : Community Airdrop Pool Part 2 - Agiex, OEX, LONG, Mainnet, etc.
        // 30% : Community Staking Rewards Pool
        // 20% : DAO Pool
        // 15% : Ecosystem Growth and Marketing Pool
        // 10% : Team Pool
        //  5% : Early Contributors Pool

        // placeholder
        _mint(address(0), (initialSupply / 100) * 10);
        _mint(address(0), (initialSupply / 100) * 10);
        _mint(address(0), (initialSupply / 100) * 30);
        _mint(address(0), (initialSupply / 100) * 20);
        _mint(address(0), (initialSupply / 100) * 15);
        _mint(address(0), (initialSupply / 100) * 10);
        _mint(address(0), (initialSupply / 100) * 5);

        require(initialSupply == totalSupply());
    }
}
