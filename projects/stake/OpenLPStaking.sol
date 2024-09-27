// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function totalSupply() external view returns (uint256);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

contract OpenLPStaking is Ownable, ReentrancyGuard, Pausable {
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
        uint256 maxLPValue;
        uint256 totalStakedLPValue;
        bool frozen;
    }

    IERC20 public lpToken;
    IERC20 public rewardToken;
    uint256 public constant SECONDS_IN_A_YEAR = 31557600;
    bool public stakingEnabled = true;
    uint256 public minStakeAmount;

    mapping(address => Stake[]) public stakes;
    StakingPlan[] public stakingPlans;

    event Staked(address indexed user, uint256 amount, uint256 duration, uint256 planId);
    event Claimed(address indexed user, uint256 stakeIndex, uint256 amount, uint256 reward);
    event Withdrawn(address indexed user, uint256 stakeIndex, uint256 amount);
    event StakingPlanAdded(uint256 planId, uint256 duration, uint256 apr, uint256 maxLPValue);
    event StakingPlanUpdated(uint256 planId, uint256 duration, uint256 apr, uint256 maxLPValue);
    event StakingEnabled(bool enabled);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event StakingPlanFrozen(uint256 planId);
    event MinStakeAmountUpdated(uint256 newMinStakeAmount);

    constructor(IERC20 _lpToken, IERC20 _rewardToken) {
        lpToken = _lpToken;
        rewardToken = _rewardToken;
        minStakeAmount = 1 ether;
    }

    function addStakingPlan(uint256 duration, uint256 apr, uint256 maxLPValue) external onlyOwner {
        require(apr <= 10000, "APR too high");
        stakingPlans.push(
            StakingPlan({duration: duration, apr: apr, maxLPValue: maxLPValue, totalStakedLPValue: 0, frozen: false})
        );
        emit StakingPlanAdded(stakingPlans.length - 1, duration, apr, maxLPValue);
    }

    function updateStakingPlan(uint256 planId, uint256 duration, uint256 apr, uint256 maxLPValue) external onlyOwner {
        require(planId < stakingPlans.length, "Invalid plan ID");
        require(apr <= 10000, "APR too high");

        StakingPlan storage plan = stakingPlans[planId];
        plan.duration = duration;
        plan.apr = apr;
        plan.maxLPValue = maxLPValue;

        emit StakingPlanUpdated(planId, duration, apr, maxLPValue);
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

        StakingPlan storage plan = stakingPlans[planId];
        uint256 lpValue = calculateLPValue(amount);
        require(plan.totalStakedLPValue + lpValue <= plan.maxLPValue, "Exceeds maximum staking LP value");

        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        stakes[msg.sender].push(
            Stake({amount: amount, startTime: block.timestamp, duration: plan.duration, claimed: false, planId: planId})
        );

        plan.totalStakedLPValue += lpValue;

        emit Staked(msg.sender, amount, plan.duration, planId);
    }

    function calculateLPValue(uint256 lpAmount) public view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(address(lpToken));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();
        address token0 = pair.token0();
        address token1 = pair.token1();

        uint256 tokenReserve;
        if (token0 == address(rewardToken)) {
            tokenReserve = uint256(reserve0);
        } else if (token1 == address(rewardToken)) {
            tokenReserve = uint256(reserve1);
        } else {
            revert("Token not in pair");
        }

        uint256 lpTokenValue = (lpAmount * tokenReserve * 2) / totalSupply;
        return lpTokenValue;
    }

    function calculateReward(Stake memory _stake) public view returns (uint256) {
        StakingPlan storage plan = stakingPlans[_stake.planId];
        uint256 lpValue = calculateLPValue(_stake.amount);
        uint256 reward = (lpValue * plan.apr * _stake.duration) / SECONDS_IN_A_YEAR / 100;
        return reward;
    }

    function claim(uint256 _stakeIndex) external nonReentrant {
        require(_stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage _stake = stakes[msg.sender][_stakeIndex];
        require(!_stake.claimed, "Already claimed");
        require(block.timestamp >= _stake.startTime + _stake.duration, "Staking period not yet over");

        uint256 reward = calculateReward(_stake);
        uint256 totalAmount = _stake.amount + reward;
        require(rewardToken.balanceOf(address(this)) >= totalAmount, "Insufficient contract balance");

        _stake.claimed = true;
        rewardToken.safeTransfer(msg.sender, totalAmount);

        StakingPlan storage plan = stakingPlans[_stake.planId];
        plan.totalStakedLPValue -= calculateLPValue(_stake.amount);

        emit Claimed(msg.sender, _stakeIndex, _stake.amount, reward);
    }

    function withdraw(uint256 _stakeIndex) external nonReentrant {
        require(_stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage _stake = stakes[msg.sender][_stakeIndex];
        require(!_stake.claimed, "Already claimed");

        uint256 amount = _stake.amount;
        _stake.claimed = true;

        StakingPlan storage plan = stakingPlans[_stake.planId];
        plan.totalStakedLPValue -= calculateLPValue(amount);
        lpToken.safeTransfer(msg.sender, amount);

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
        require(
            tokenAddress != address(lpToken) && tokenAddress != address(rewardToken),
            "Cannot recover staking or reward tokens"
        );
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    }
}
