// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IPancakeFactory.sol";
import "./interface/IPancakeRouter02.sol";

contract FairLaunch is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IPancakeRouter02 public swapRouter;
    mapping(address => uint256) public exchangedAmount;

    struct LaunchConfig {
        IERC20 tokenA;
        IERC20 tokenB;
        uint256 exchangeRate;
        uint256 maxExchangePerAddress;
        uint256 maxTotalExchange;
        uint256 minTotalExchange;
        uint256 totalExchanged;
        address tokenABPair;
        address passToken;
        uint256 minPassToken;
        uint64 startTime;
        uint64 endTime;
    }

    LaunchConfig public config;

    event Exchanged(address indexed user, uint256 tokenBAmount, uint256 tokenAAmount);
    event Refunded(address indexed user, uint256 tokenAAmount);
    event Claimed(address indexed user, uint256 tokenAAmount);
    event SwapPoolCreated(address indexed tokenA, address indexed tokenB, uint256 tokenAAmount, uint256 tokenBAmount);

    constructor(IPancakeRouter02 _swapRouter, LaunchConfig memory _config) {
        require(_config.tokenA != _config.tokenB, "Token A and Token B cannot be the same");
        require(_config.exchangeRate > 0, "Exchange rate must be greater than 0");
        require(_config.maxExchangePerAddress > 0, "Max exchange per address must be greater than 0");
        require(_config.maxTotalExchange > 0, "Max total exchange must be greater than 0");
        require(_config.minTotalExchange > 0, "Min total exchange must be greater than 0");
        require(_config.startTime < _config.endTime, "Start time must be before end time");
        require(_config.endTime > block.timestamp, "End time must be in the future");
        require(
            _config.minTotalExchange <= _config.maxTotalExchange,
            "Min total exchange must be less than or equal to max total exchange"
        );

        swapRouter = _swapRouter;
        config = _config;
    }

    modifier onlyStarted() {
        require(block.timestamp >= config.startTime && block.timestamp <= config.endTime, "Launch not started");
        _;
    }

    modifier onlyEnded() {
        require(block.timestamp > config.endTime, "Launch not ended");
        _;
    }

    function withdrawRemainingTokenA() external onlyOwner onlyEnded {
        require(config.totalExchanged < config.minTotalExchange, "Withdraw not available");
        uint256 remainingTokenA = config.tokenA.balanceOf(address(this));
        config.tokenA.safeTransfer(msg.sender, remainingTokenA);
    }

    function exchange(uint256 tokenBAmount) external nonReentrant onlyStarted {
        uint256 tokenAAmount = tokenBAmount * config.exchangeRate;
        uint256 userExchangedAmount = exchangedAmount[msg.sender] + tokenAAmount;

        require(userExchangedAmount <= config.maxExchangePerAddress, "Exceeds max exchange per address");
        require(config.totalExchanged + tokenAAmount <= config.maxTotalExchange, "Exceeds max total exchange");
        require(
            config.minPassToken <= 0 || IERC20(config.passToken).balanceOf(msg.sender) >= config.minPassToken,
            "Not Enough Swap Token"
        );

        config.tokenB.safeTransferFrom(msg.sender, address(this), tokenBAmount);

        exchangedAmount[msg.sender] = userExchangedAmount;
        config.totalExchanged += tokenAAmount;

        emit Exchanged(msg.sender, tokenBAmount, tokenAAmount);
    }

    function claim() external nonReentrant onlyEnded {
        require(config.totalExchanged < config.minTotalExchange, "Claim not available");
        uint256 tokenAAmount = exchangedAmount[msg.sender];
        require(tokenAAmount > 0, "No tokens to claim");

        exchangedAmount[msg.sender] = 0;
        config.tokenA.safeTransfer(msg.sender, tokenAAmount);

        emit Claimed(msg.sender, tokenAAmount);
    }

    function refund() external nonReentrant onlyEnded {
        require(config.totalExchanged < config.minTotalExchange, "Refund not available");
        uint256 tokenAAmount = exchangedAmount[msg.sender];
        require(tokenAAmount > 0, "No tokens to refund");
        uint256 tokenBAmount = tokenAAmount / config.exchangeRate;
        require(tokenBAmount <= config.tokenB.balanceOf(address(this)), "Not enough tokens to refund");

        exchangedAmount[msg.sender] = 0;
        config.totalExchanged -= tokenAAmount;

        config.tokenB.safeTransfer(msg.sender, tokenBAmount);

        emit Refunded(msg.sender, tokenAAmount);
    }

    function createSwapPool() external nonReentrant onlyEnded {
        require(config.totalExchanged >= config.minTotalExchange, "Not reached minimum total exchange");
        require(config.tokenABPair == address(0), "Pair already created");

        uint256 tokenBAmount = config.tokenB.balanceOf(address(this));
        uint256 tokenAAmount = tokenBAmount * config.exchangeRate;
        require(tokenAAmount <= config.tokenA.balanceOf(address(this)), "Not enough token A");

        // 1. Approve Swap Router to spend Token A and Token B
        config.tokenA.approve(address(swapRouter), tokenAAmount);
        config.tokenB.approve(address(swapRouter), tokenBAmount);

        // 2. Add liquidity to Swap
        swapRouter.addLiquidity(
            address(config.tokenA),
            address(config.tokenB),
            tokenAAmount,
            tokenBAmount,
            0, // min amount of Token A
            0, // min amount of Token B
            address(0x000000000000000000000000000000000000dEaD),
            block.timestamp + 1200 // Deadline for adding liquidity
        );

        // 3. Set the pair (Token A and Token B)
        IPancakeFactory factory = IPancakeFactory(swapRouter.factory());
        config.tokenABPair = factory.getPair(address(config.tokenA), address(config.tokenB));

        uint256 tokenA = config.tokenA.balanceOf(address(this));
        if (tokenA > 0) {
            config.tokenA.safeTransfer(owner(), tokenA);
        }

        uint256 tokenB = config.tokenB.balanceOf(address(this));
        if (tokenB > 0) {
            config.tokenB.safeTransfer(owner(), tokenB);
        }

        emit SwapPoolCreated(address(config.tokenA), address(config.tokenB), tokenAAmount, tokenBAmount);
    }
}
