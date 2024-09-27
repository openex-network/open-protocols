// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title Open Token Lock
 */
contract OpenTokenLock is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    struct Config {
        uint128 periodFinish;
        uint128 periodStart;
        address token;
        address receiver;
        uint256 amount;
    }
    Config public config;

    event TokenLocked(uint256 amount);
    event TokenUnlocked(uint256 amount);
    event PeriodFinishUpdated(uint128 newPeriodFinish);
    event ReceiverUpdated(address newReceiver);
    event EmergencyWithdraw(address token, uint256 amount);

    constructor(address _token, address _receiver, uint128 _periodStart, uint128 _duration) {
        require(address(_token) != address(0), "OTL: _token cannot be the zero address");
        require(_receiver != address(0), "OTL: _receiver cannot be the zero address");
        require(_periodStart >= block.timestamp, "OTL: _periodStart shouldn't be in the past");
        require(_duration > 0, "OTL: Invalid duration");

        uint128 _periodFinish = _periodStart + _duration;
        config.token = _token;
        config.receiver = _receiver;
        config.periodStart = _periodStart;
        config.periodFinish = _periodFinish;
        config.amount = 0;
    }

    function lock(uint256 _tokenAmount) external nonReentrant whenNotPaused {
        require(block.timestamp < config.periodStart, "OTL: Lock period has already started");

        IERC20(config.token).safeTransferFrom(msg.sender, address(this), _tokenAmount);
        config.amount += _tokenAmount;

        emit TokenLocked(_tokenAmount);
    }

    function unlock() external nonReentrant whenNotPaused {
        require(block.timestamp > config.periodStart, "OTL: Lock period has not started");

        uint256 unlockedTokenAmount = getUnlockedTokenAmount();
        require(unlockedTokenAmount > 0, "OTL: No token to unlock");

        IERC20(config.token).safeTransfer(config.receiver, unlockedTokenAmount);

        emit TokenUnlocked(unlockedTokenAmount);
    }

    function getUnlockedTokenAmount() public view returns (uint256) {
        uint256 balance = IERC20(config.token).balanceOf(address(this));
        uint256 lockedAmount = getLockedTokenAmount();
        if (balance <= lockedAmount) {
            return 0;
        }
        return balance - lockedAmount;
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

    function getLockStatus()
        public
        view
        returns (
            uint256 totalLocked,
            uint256 currentlyLocked,
            uint256 totalUnlocked,
            uint256 actualBalance,
            uint256 withdrawable
        )
    {
        totalLocked = config.amount;
        currentlyLocked = getLockedTokenAmount();
        totalUnlocked = totalLocked - currentlyLocked;
        actualBalance = IERC20(config.token).balanceOf(address(this));
        withdrawable = getUnlockedTokenAmount();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updatePeriodFinish(uint128 newPeriodFinish) external onlyOwner {
        require(newPeriodFinish > config.periodFinish, "New period finish must be later");
        config.periodFinish = newPeriodFinish;
        emit PeriodFinishUpdated(newPeriodFinish);
    }

    function updateReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Invalid receiver address");
        config.receiver = newReceiver;
        emit ReceiverUpdated(newReceiver);
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(paused(), "Contract must be paused");
        IERC20(token).safeTransfer(owner(), amount);
        emit EmergencyWithdraw(token, amount);
    }
}
