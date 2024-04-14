// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "./FairLaunch.sol";

contract LaunchFactory is Ownable {
    using SafeERC20 for IERC20;
    IPancakeRouter02 public pancakeRouter;
    address[] public launches;

    address public passToken;
    uint256 public minTokenCreate;
    uint256 public minTokenExchange;

    event LaunchCreated(address indexed launch, address indexed creator, uint256 index);

    constructor(IPancakeRouter02 _pancakeRouter) {
        pancakeRouter = _pancakeRouter;
    }

    function updatePassToken(
        address _passToken,
        uint256 _minTokenCreate,
        uint256 _minTokenExchange
    ) external onlyOwner {
        passToken = _passToken;
        minTokenCreate = _minTokenCreate;
        minTokenExchange = _minTokenExchange;
    }

    function createLaunch(FairLaunch.LaunchConfig memory _config) external {
        require(
            minTokenCreate == 0 || IERC20(passToken).balanceOf(msg.sender) >= minTokenCreate,
            "Not Enough Pass Token"
        );
        require(_config.tokenA != _config.tokenB, "Token A and Token B cannot be the same");

        if (passToken != address(0)) {
            _config.passToken = passToken;
            _config.minPassToken = minTokenExchange;
        }

        uint256 launchTokenAmount = _config.maxTotalExchange * 2;
        require(_config.tokenA.balanceOf(msg.sender) >= launchTokenAmount, "Token A Not Enough");

        _config.tokenA.safeTransferFrom(msg.sender, address(this), launchTokenAmount);
        FairLaunch newLaunch = new FairLaunch(pancakeRouter, _config);
        _config.tokenA.safeTransfer(address(newLaunch), launchTokenAmount);
        launches.push(address(newLaunch));
        newLaunch.transferOwnership(msg.sender);

        emit LaunchCreated(address(newLaunch), msg.sender, launches.length - 1);
    }

    function totalLaunch() public view returns (uint256) {
        return launches.length;
    }
}
