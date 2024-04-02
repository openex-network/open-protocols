// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OpenReward is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public stakeToken;
    IERC20 public rewardToken;

    struct Config {
        uint256 startTime;
        uint256 endTime;
        uint256 rewardRate;
    }

    struct RewardInfo {
        address stakeToken;
        address rewardToken;
        uint256 rewardPerToken;
        uint256 totalSupply;
        uint256 balance;
        uint256 earned;
        Config config;
    }

    Config public rewardConfig;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalSupply;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balances;

    event RewardAdded(uint256 tokenAmount, uint256 startTime, uint256 endTime);
    event Staked(address indexed user, uint256 tokenAmount);
    event Withdraw(address indexed user, uint256 tokenAmount);
    event Claimed(address indexed user, uint256 rewardAmount);

    constructor(address _stakeToken, address _rewardToken) {
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function setRewardConfig(uint256 _startTime, uint256 _endTime, uint256 _totalReward) external onlyOwner {
        require(block.timestamp < rewardConfig.startTime || block.timestamp > rewardConfig.endTime, "Ongoing reward");
        require(_endTime > _startTime, "End time must be after start time");

        rewardConfig.startTime = _startTime;
        rewardConfig.endTime = _endTime;
        rewardConfig.rewardRate = _totalReward.div(_endTime.sub(_startTime));

        rewardToken.safeTransferFrom(msg.sender, address(this), _totalReward);

        emit RewardAdded(_totalReward, _startTime, _endTime);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        if (block.timestamp < rewardConfig.startTime) {
            return rewardConfig.startTime;
        } else if (block.timestamp < rewardConfig.endTime) {
            return block.timestamp;
        } else {
            return rewardConfig.endTime;
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardConfig.rewardRate).mul(1e18).div(totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(
                rewards[account]
            );
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");

        totalSupply = totalSupply.add(amount);
        balances[msg.sender] = balances[msg.sender].add(amount);
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(balances[msg.sender] >= amount, "Not enough balance");

        totalSupply = totalSupply.sub(amount);
        balances[msg.sender] = balances[msg.sender].sub(amount);
        stakeToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function claim() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);

            emit Claimed(msg.sender, reward);
        }
    }

    function expectedReward(uint256 stakeAmount, uint256 timeInSeconds) public view returns (uint256) {
        if (totalSupply == 0) {
            return 0;
        }
        uint256 rewardAmount = stakeAmount.mul(rewardConfig.rewardRate).mul(timeInSeconds).div(
            totalSupply.add(stakeAmount)
        );
        return rewardAmount;
    }

    function rewardInfo(address user) external view returns (RewardInfo memory) {
        return
            RewardInfo({
                stakeToken: address(stakeToken),
                rewardToken: address(rewardToken),
                rewardPerToken: rewardPerToken(),
                totalSupply: totalSupply,
                balance: balances[user],
                earned: earned(user),
                config: rewardConfig
            });
    }
}
