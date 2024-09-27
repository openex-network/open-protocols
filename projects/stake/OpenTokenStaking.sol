// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract OpenTokenStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 duration;
        bool claimed;
        uint256 planId;
    }

    struct StakingPlan {
        uint256 duration;
        uint256 apr;
        uint256 maxStake;
        uint256 totalStaked;
        bool frozen;
    }

    IERC20 public stakingToken;
    uint256 public constant SECONDS_IN_A_YEAR = 31557600;
    bool public stakingEnabled = true;
    uint256 public minStakeAmount;

    mapping(address => Stake[]) public stakes;
    StakingPlan[] public stakingPlans;

    event Staked(address indexed user, uint256 amount, uint256 duration, uint256 planId);
    event Claimed(address indexed user, uint256 stakeIndex, uint256 amount, uint256 reward);
    event Withdrawn(address indexed user, uint256 stakeIndex, uint256 amount);
    event StakingPlanAdded(uint256 planId, uint256 duration, uint256 apr, uint256 maxStake);
    event StakingPlanUpdated(uint256 planId, uint256 duration, uint256 apr, uint256 maxStake);
    event StakingEnabled(bool enabled);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event StakingPlanFrozen(uint256 planId);
    event MinStakeAmountUpdated(uint256 newMinStakeAmount);

    constructor(IERC20 _stakingToken) {
        stakingToken = _stakingToken;
        minStakeAmount = 1 ether;
    }

    function addStakingPlan(uint256 duration, uint256 apr, uint256 maxStake) external onlyOwner {
        require(apr <= 10000, "APR too high");
        stakingPlans.push(
            StakingPlan({duration: duration, apr: apr, maxStake: maxStake, totalStaked: 0, frozen: false})
        );
        emit StakingPlanAdded(stakingPlans.length - 1, duration, apr, maxStake);
    }

    function updateStakingPlan(uint256 planId, uint256 duration, uint256 apr, uint256 maxStake) external onlyOwner {
        require(planId < stakingPlans.length, "Invalid plan ID");
        require(apr <= 10000, "APR too high");

        StakingPlan storage plan = stakingPlans[planId];
        plan.duration = duration;
        plan.apr = apr;
        plan.maxStake = maxStake;

        emit StakingPlanUpdated(planId, duration, apr, maxStake);
    }

    function setStakingEnabled(bool enabled) external onlyOwner {
        stakingEnabled = enabled;
        emit StakingEnabled(enabled);
    }

    function stake(uint256 amount, uint256 planId) external nonReentrant whenNotPaused {
        require(stakingEnabled, "Staking is currently disabled");
        require(amount >= minStakeAmount, "Stake amount too low");
        require(planId < stakingPlans.length, "Invalid plan ID");
        require(!stakingPlans[planId].frozen, "Staking plan is frozen");
        require(amount > 0, "Cannot stake zero amount");

        StakingPlan storage plan = stakingPlans[planId];
        require(plan.totalStaked + amount <= plan.maxStake, "Exceeds maximum staking limit");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        stakes[msg.sender].push(
            Stake({amount: amount, startTime: block.timestamp, duration: plan.duration, claimed: false, planId: planId})
        );

        plan.totalStaked += amount;

        emit Staked(msg.sender, amount, plan.duration, planId);
    }

    function calculateReward(Stake memory _stake) public view returns (uint256) {
        StakingPlan storage plan = stakingPlans[_stake.planId];
        uint256 reward = (_stake.amount * plan.apr * _stake.duration) / SECONDS_IN_A_YEAR / 100;
        return reward;
    }

    function claim(uint256 _stakeIndex) external nonReentrant whenNotPaused {
        require(_stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage _stake = stakes[msg.sender][_stakeIndex];
        require(!_stake.claimed, "Already claimed");
        require(block.timestamp >= _stake.startTime + _stake.duration, "Staking period not yet over");

        uint256 reward = calculateReward(_stake);
        uint256 totalAmount = _stake.amount + reward;
        require(stakingToken.balanceOf(address(this)) >= totalAmount, "Insufficient contract balance");

        _stake.claimed = true;
        stakingToken.safeTransfer(msg.sender, totalAmount);

        StakingPlan storage plan = stakingPlans[_stake.planId];
        plan.totalStaked -= _stake.amount;

        emit Claimed(msg.sender, _stakeIndex, _stake.amount, reward);
    }

    function withdraw(uint256 _stakeIndex) external nonReentrant whenNotPaused {
        require(_stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage _stake = stakes[msg.sender][_stakeIndex];
        require(!_stake.claimed, "Already claimed");

        uint256 amount = _stake.amount;
        _stake.claimed = true;

        StakingPlan storage plan = stakingPlans[_stake.planId];
        plan.totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, _stakeIndex, amount);
    }

    function getStakes(address staker) external view returns (Stake[] memory) {
        return stakes[staker];
    }

    function getStakesCount(address staker) external view returns (uint256) {
        return stakes[staker].length;
    }

    function getStakingPlans() external view returns (StakingPlan[] memory) {
        return stakingPlans;
    }

    function getStakingPlansCount() external view returns (uint256) {
        return stakingPlans.length;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(paused(), "Contract must be paused");
        IERC20(token).safeTransfer(owner(), amount);
        emit EmergencyWithdraw(token, amount);
    }

    function freezeStakingPlan(uint256 planId) external onlyOwner {
        require(planId < stakingPlans.length, "Invalid plan ID");
        stakingPlans[planId].frozen = true;
        emit StakingPlanFrozen(planId);
    }

    function setMinStakeAmount(uint256 _minStakeAmount) external onlyOwner {
        minStakeAmount = _minStakeAmount;
        emit MinStakeAmountUpdated(_minStakeAmount);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "Cannot recover staking token");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    }
}
