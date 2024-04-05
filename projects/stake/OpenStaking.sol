// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Open Staking
 */
contract OpenStaking is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;

    struct Config {
        uint128 periodFinish;
        uint128 periodStart;
        uint256 totalReward;
    }

    IERC20 private _stakeToken;
    Config private _config;
    mapping(address => uint256) private _lastStakedTime;

    event RewardAdded(uint256 tokenAmount);
    event Staked(address indexed user, uint256 tokenAmount);
    event Claimed(address indexed user, uint256 share);

    modifier afterStakingPeriod(address account) {
        require(
            block.timestamp > _lastStakedTime[account] + 3600,
            "Open Staking: Operation not allowed yet. Wait for 1 hour after staking."
        );
        _;
    }

    constructor(
        string memory _symbol,
        IERC20 _stakeTokenAddress,
        uint128 _periodStart,
        uint128 _rewardsDuration
    ) ERC20("Open Staking Share", _symbol) {
        require(
            address(_stakeTokenAddress) != address(0),
            "Open Staking: _stakeTokenAddress cannot be the zero address"
        );
        _stakeToken = _stakeTokenAddress;
        _setPeriod(_periodStart, _rewardsDuration);
    }

    function _setPeriod(uint128 _periodStart, uint128 _rewardsDuration) internal {
        require(_periodStart >= block.timestamp, "Open Staking: _periodStart shouldn't be in the past");
        require(_rewardsDuration > 0, "Open Staking: Invalid rewards duration");

        uint128 _periodFinish = _periodStart + _rewardsDuration;
        _config.periodStart = _periodStart;
        _config.periodFinish = _periodFinish;
        _config.totalReward = 0;
    }

    function addRewardToken(uint256 _tokenAmount) external nonReentrant {
        Config memory cfg = _config;
        require(block.timestamp < cfg.periodFinish, "Open Staking: Adding rewards is forbidden");

        _stakeToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);
        cfg.totalReward += _tokenAmount;
        _config = cfg;

        emit RewardAdded(_tokenAmount);
    }

    function stake(uint256 _tokenAmount) external nonReentrant {
        require(_tokenAmount > 0, "Open Staking: Should at least stake something");
        require(
            block.timestamp < _config.periodFinish && block.timestamp > _config.periodStart,
            "Open Staking: Staking is forbidden"
        );

        uint256 totalToken = getTokenPool();
        uint256 totalShare = totalSupply();

        _stakeToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);

        if (totalShare == 0 || totalToken == 0) {
            _mint(msg.sender, _tokenAmount);
        } else {
            uint256 _share = (_tokenAmount * totalShare) / totalToken;
            _mint(msg.sender, _share);
        }

        _lastStakedTime[msg.sender] = block.timestamp;

        emit Staked(msg.sender, _tokenAmount);
    }

    function claim(uint256 _share) external nonReentrant afterStakingPeriod(msg.sender) {
        require(_share > 0, "Open Staking: Should at least unstake something");

        uint256 totalToken = getTokenPool();
        uint256 totalShare = totalSupply();

        _burn(msg.sender, _share);

        uint256 _tokenAmount = (_share * totalToken) / totalShare;
        _stakeToken.safeTransfer(msg.sender, _tokenAmount);

        emit Claimed(msg.sender, _share);
    }

    function transfer(address recipient, uint256 amount) public override afterStakingPeriod(msg.sender) returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override afterStakingPeriod(sender) returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function getTokenPool() public view returns (uint256) {
        return _stakeToken.balanceOf(address(this)) - frozenRewards();
    }

    function frozenRewards() public view returns (uint256) {
        Config memory cfg = _config;

        uint256 time = block.timestamp;
        uint256 remainingTime;
        uint256 duration = uint256(cfg.periodFinish) - uint256(cfg.periodStart);

        if (time <= cfg.periodStart) {
            remainingTime = duration;
        } else if (time >= cfg.periodFinish) {
            remainingTime = 0;
        } else {
            remainingTime = cfg.periodFinish - time;
        }

        return (remainingTime * uint256(cfg.totalReward)) / duration;
    }

    function config() public view returns (Config memory) {
        return _config;
    }

    function token() public view returns (address) {
        return address(_stakeToken);
    }
}
