// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./Token.sol";

contract TokenFactory is Ownable {
    using SafeERC20 for IERC20;

    address[] public tokens;
    address public passToken;
    uint256 public minPassToken;

    event TokenCreated(address indexed token, address indexed creator, uint256 index);

    constructor() {}

    function updatePassToken(address _passToken, uint256 _minPassToken) external onlyOwner {
        passToken = _passToken;
        minPassToken = _minPassToken;
    }

    function createToken(string memory _name, string memory _symbol, uint256 _initialSupply) external {
        require(bytes(_name).length > 0, "Invalid name");
        require(bytes(_symbol).length > 0, "Invalid symbol");
        require(_initialSupply > 0, "Invalid initial supply");
        require(minPassToken == 0 || IERC20(passToken).balanceOf(msg.sender) >= minPassToken, "Not Enough Pass Token");

        Token newToken = new Token(_name, _symbol, _initialSupply);
        IERC20(newToken).safeTransfer(msg.sender, _initialSupply);
        tokens.push(address(newToken));

        emit TokenCreated(address(newToken), msg.sender, tokens.length - 1);
    }

    function totalTokens() public view returns (uint256) {
        return tokens.length;
    }
}
