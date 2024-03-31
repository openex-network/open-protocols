// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Open Time Lock
 */
contract OpenTimeLock is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Config {
        uint128 periodFinish;
        uint128 periodStart;
        address token;
        address reciever;
        uint256 amount;
    }
    Config public config;

    event TokenLocked(uint256 amount);
    event TokenUnlocked(uint256 amount);

    constructor(address _token, address _reciever, uint128 _periodStart, uint128 _duration) {
        require(address(_token) != address(0), "Open Time Lock: _token cannot be the zero address");
        require(_periodStart >= block.timestamp, "Open Time Lock: _periodStart shouldn't be in the past");
        require(_duration > 0, "Open Time Lock: Invalid duration");

        uint128 _periodFinish = _periodStart + _duration;
        config.token = _token;
        config.reciever = _reciever;
        config.periodStart = _periodStart;
        config.periodFinish = _periodFinish;
        config.amount = 0;
    }

    function lock(uint256 _tokenAmount) external nonReentrant {
        require(block.timestamp < config.periodFinish, "Open Time Lock: Lock period has ended");

        IERC20(config.token).safeTransferFrom(msg.sender, address(this), _tokenAmount);
        config.amount += _tokenAmount;

        emit TokenLocked(_tokenAmount);
    }

    function unlock() external nonReentrant {
        require(block.timestamp < config.periodFinish, "Open Time Lock: Lock period has ended");
        require(block.timestamp > config.periodStart, "Open Time Lock: Lock period has not started");

        uint256 unlockedTokenAmount = getUnlockedTokenAmount();
        IERC20(config.token).safeTransfer(config.reciever, unlockedTokenAmount);

        emit TokenUnlocked(unlockedTokenAmount);
    }

    function getUnlockedTokenAmount() public view returns (uint256) {
        return IERC20(config.token).balanceOf(address(this)) - getLockedTokenAmount();
    }

    function getLockedTokenAmount() public view returns (uint256) {
        uint256 time = block.timestamp;
        uint256 remainingTime;
        uint256 duration = uint256(config.periodFinish) - uint256(config.periodStart);

        if (time <= config.periodStart) {
            remainingTime = duration;
        } else if (time >= config.periodFinish) {
            remainingTime = 0;
        } else {
            remainingTime = config.periodFinish - time;
        }

        return (remainingTime * config.amount) / duration;
    }
}
