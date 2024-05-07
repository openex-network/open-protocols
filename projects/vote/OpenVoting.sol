// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OpenVoting is ERC20, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public powerToken;

    struct Proposal {
        string title;
        address proposer;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        bool closed;
    }

    struct Config {
        uint64 minDuration;
        uint64 maxDuration;
        uint64 minCooldown;
        uint256 proposalAmountPerHour;
    }

    Proposal[] proposals;
    Proposal public openProposal;
    Config public config;
    mapping(address => uint256) public lastVotingRound;

    event ProposalCreated(address indexed proposer, string title, uint256 duration);
    event Voted(address indexed voter, bool agree, uint256 amount);
    event Withdraw(address indexed voter, uint256 amount);
    event TransferAction(address indexed from, address indexed to, uint256 amount);

    constructor(string memory _symbol, address _powerToken, Config memory _config) ERC20("Open Voting Token", _symbol) {
        powerToken = IERC20(_powerToken);
        config = _config;
    }

    function createProposal(string memory title, uint256 duration) public nonReentrant whenNotPaused {
        require(duration >= config.minDuration, "Invalid duration");
        require(duration <= config.maxDuration, "Invalid duration");
        require(openProposal.endTime + config.minCooldown < block.timestamp, "Not cooldown");

        uint256 amount = (config.proposalAmountPerHour * duration) / 3600;

        require(powerToken.balanceOf(msg.sender) >= amount, "Not enough power token");

        powerToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);

        openProposal = Proposal({
            title: title,
            proposer: msg.sender,
            endTime: block.timestamp + duration,
            forVotes: 0,
            againstVotes: 0,
            closed: false
        });

        proposals.push(openProposal);

        lastVotingRound[msg.sender] = proposals.length;

        emit ProposalCreated(msg.sender, title, duration);
    }

    function vote(uint256 amount, bool agree) public nonReentrant whenNotPaused {
        require(block.timestamp <= openProposal.endTime, "Proposal voting time is up");
        require(!openProposal.closed, "Proposal is closed");
        require(powerToken.balanceOf(msg.sender) >= amount, "Not enough power token");
        powerToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);

        if (agree) {
            openProposal.forVotes = openProposal.forVotes + amount;
        } else {
            openProposal.againstVotes = openProposal.againstVotes + amount;
        }

        lastVotingRound[msg.sender] = proposals.length;

        emit Voted(msg.sender, agree, amount);
    }

    function withdraw() public nonReentrant whenNotPaused {
        require(
            openProposal.endTime < block.timestamp || lastVotingRound[msg.sender] < proposals.length,
            "There is an ongoing proposal"
        );
        uint256 balance = balanceOf(msg.sender);
        _burn(msg.sender, balance);
        powerToken.safeTransfer(msg.sender, balance);

        emit Withdraw(msg.sender, balance);
    }

    function closeProposal(bool _closed) public onlyOwner {
        openProposal.closed = _closed;
    }

    function updateConfig(Config memory _config) public onlyOwner {
        require(_config.minDuration <= _config.maxDuration, "Invalid duration");
        require(_config.proposalAmountPerHour > 0, "Invalid amount per hour");
        config = _config;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        emit TransferAction(msg.sender, to, amount);
        return false;
    }
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        emit TransferAction(from, to, amount);
        return false;
    }
}
