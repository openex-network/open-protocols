// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OpenAirdrop is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant KYC_USER = keccak256("KYC_USER");
    bytes32 public constant VALIDATOR = keccak256("VALIDATOR");
    IERC20 public rewardToken;

    struct Reward {
        uint256 reward;
        uint256 totalReward;
        uint256 startTime;
        uint256 duration;
    }

    mapping(address => Reward) public rewards;

    // Events
    event RewardAdded(address indexed user, uint256 tokenAmount);
    event Claimed(address indexed user, uint256 share);
    event KycUserChanged(address indexed user, bool isKyc);

    constructor(address _rewardToken) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        rewardToken = IERC20(_rewardToken);
    }

    function addReward(
        address _user,
        uint256 _totalReward,
        uint256 _startTime,
        uint256 _duration
    ) public nonReentrant onlyRole(VALIDATOR) {
        require(_totalReward > 0 && _duration > 0, "Total reward and duration must be greater than zero");
        require(rewards[_user].reward == 0, "Rewards already added");
        require(rewards[_user].totalReward == 0, "Total rewards already added");
        require(_startTime >= block.timestamp, "Start time must be in the future");

        rewards[_user] = Reward(_totalReward, _totalReward, _startTime, _duration);
        rewardToken.safeTransferFrom(msg.sender, address(this), _totalReward);

        emit RewardAdded(_user, _totalReward);
    }

    function claimReward() public nonReentrant onlyRole(KYC_USER) {
        require(rewards[_msgSender()].reward > 0, "No rewards available");

        Reward storage reward = rewards[_msgSender()];
        uint256 amount = unlockedRewards(_msgSender());
        reward.reward -= amount;
        rewardToken.safeTransfer(_msgSender(), amount);

        emit Claimed(_msgSender(), amount);
    }

    function unlockedRewards(address _user) public view returns (uint256) {
        return rewards[_user].reward - frozenRewards(_user);
    }

    function frozenRewards(address _user) public view returns (uint256) {
        Reward memory cfg = rewards[_user];

        if (cfg.duration == 0) {
            return 0;
        }

        uint256 time = block.timestamp;
        uint256 remainingTime;
        uint256 endTime = uint256(cfg.startTime) + uint256(cfg.duration);

        if (time <= cfg.startTime) {
            remainingTime = cfg.duration;
        } else if (time >= endTime) {
            remainingTime = 0;
        } else {
            remainingTime = endTime - time;
        }

        return (remainingTime * uint256(cfg.totalReward)) / cfg.duration;
    }

    function addKycUser(address _user) public onlyRole(VALIDATOR) {
        _grantRole(KYC_USER, _user);

        emit KycUserChanged(_user, true);
    }

    function renounceKycUser(address _user) public onlyRole(VALIDATOR) {
        _revokeRole(KYC_USER, _user);

        emit KycUserChanged(_user, false);
    }
}
