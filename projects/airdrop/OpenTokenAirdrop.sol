// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract OpenTokenAirdrop is Ownable, ReentrancyGuard, EIP712, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    IERC20 public airdropToken;
    uint256 public constant INSTANT_REWARD_PERCENTAGE = 20;
    uint256 public constant RELEASE_DURATION = 720 days;
    address public signerAddress;

    uint256 public releaseStartTime;
    uint256 public totalRegisteredAmount;
    uint256 public totalReleasedAmount;

    mapping(address => uint256) public registeredAmounts;
    mapping(address => uint256) public vestingReleasedAmounts;
    mapping(address => uint256) public lastClaimedTimestamp;
    mapping(address => bool) public hasRegistered;

    mapping(address => bool) public isLocked;
    mapping(address => uint256) public nonces;
    mapping(address => address) public updatedAddress;

    event Register(address indexed user, uint256 amount, uint256 instantReward, uint256 totalVested);
    event SignerAddressUpdated(address indexed newSignerAddress);
    event ReleaseStartTimeSet(uint256 startTime);
    event Locked(address indexed user);
    event Unlocked(address indexed user, address newWithdrawAddress);
    event Released(address indexed user, address indexed withdrawAddress, uint256 amount);

    bytes32 private constant CLAIM_TYPEHASH = keccak256("AirdropClaim(address account,uint256 amount,uint256 nonce)");
    bytes32 private constant UNLOCK_TYPEHASH =
        keccak256("UnlockRequest(address account,uint256 nonce,address newWithdrawAddress)");

    constructor(IERC20 _airdropToken, address _signerAddress, uint256 _releaseStartTime) EIP712("EIP712Airdrop", "1") {
        airdropToken = _airdropToken;
        signerAddress = _signerAddress;
        releaseStartTime = _releaseStartTime;
    }

    function registerAirdropAmount(
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        require(!hasRegistered[msg.sender], "Tokens already registered");
        require(releaseStartTime > 0, "Start time not set");
        require(block.timestamp >= releaseStartTime, "Not started yet");
        require(!isLocked[msg.sender], "Account is locked");

        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, msg.sender, amount, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        require(signer == signerAddress, "Invalid signature");

        uint256 instantReward = (amount * INSTANT_REWARD_PERCENTAGE) / 100;
        uint256 vestingAmount = amount - instantReward;

        require(
            airdropToken.balanceOf(address(this)) >= totalRegisteredAmount + instantReward + vestingAmount,
            "Insufficient contract balance"
        );

        address withdrawAddress = updatedAddress[msg.sender] != address(0) ? updatedAddress[msg.sender] : msg.sender;

        airdropToken.safeTransfer(withdrawAddress, instantReward);

        registeredAmounts[msg.sender] = amount;
        vestingReleasedAmounts[msg.sender] = 0;
        lastClaimedTimestamp[msg.sender] = block.timestamp;
        hasRegistered[msg.sender] = true;

        totalRegisteredAmount += instantReward + vestingAmount;
        totalReleasedAmount += instantReward;

        emit Register(msg.sender, amount, instantReward, vestingAmount);
    }

    function releaseVestedTokens() external nonReentrant whenNotPaused {
        require(block.timestamp >= releaseStartTime, "Releasing not started yet");
        require(!isLocked[msg.sender], "Account is locked");

        uint256 totalReleasableAmount = calculateReleasableAmount(msg.sender);
        require(totalReleasableAmount > 0, "No tokens to release");

        uint256 releasableAmount = totalReleasableAmount - vestingReleasedAmounts[msg.sender];
        require(releasableAmount > 0, "No tokens to release");

        vestingReleasedAmounts[msg.sender] += releasableAmount;
        lastClaimedTimestamp[msg.sender] = block.timestamp;
        totalReleasedAmount += releasableAmount;

        address withdrawAddress = updatedAddress[msg.sender] != address(0) ? updatedAddress[msg.sender] : msg.sender;

        airdropToken.safeTransfer(withdrawAddress, releasableAmount);

        emit Released(msg.sender, withdrawAddress, releasableAmount);
    }

    function calculateReleasableAmount(address account) public view returns (uint256) {
        if (registeredAmounts[account] == 0 || releaseStartTime > block.timestamp || releaseStartTime == 0) {
            return 0;
        }

        uint256 elapsedTime = block.timestamp - releaseStartTime;
        uint256 totalVested = (registeredAmounts[account] * (100 - INSTANT_REWARD_PERCENTAGE)) / 100;

        if (elapsedTime >= RELEASE_DURATION) {
            return totalVested;
        } else {
            return (totalVested * elapsedTime) / RELEASE_DURATION;
        }
    }

    function lock() external whenNotPaused {
        require(!isLocked[msg.sender], "Account is already locked");
        isLocked[msg.sender] = true;
        emit Locked(msg.sender);
    }

    function unlock(uint256 nonce, address newWithdrawAddress, bytes calldata signature) external whenNotPaused {
        require(isLocked[msg.sender], "Account is not locked");

        bytes32 structHash = keccak256(abi.encode(UNLOCK_TYPEHASH, msg.sender, nonce, newWithdrawAddress));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        require(signer == signerAddress, "Invalid signature");
        require(nonce == nonces[msg.sender], "Invalid nonce");

        nonces[msg.sender]++;
        isLocked[msg.sender] = false;
        updatedAddress[msg.sender] = newWithdrawAddress;

        emit Unlocked(msg.sender, newWithdrawAddress);
    }

    function updateSignerAddress(address _newSignerAddress) external onlyOwner {
        signerAddress = _newSignerAddress;
        emit SignerAddressUpdated(_newSignerAddress);
    }

    function updateReleaseStartTime(uint256 _startTime) external onlyOwner {
        require(releaseStartTime > block.timestamp || releaseStartTime == 0, "Already started");
        require(_startTime > block.timestamp, "Release start time must be in the future");
        releaseStartTime = _startTime;
        emit ReleaseStartTimeSet(_startTime);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(IERC20 token) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "no tokens to withdraw");
        token.transfer(owner(), balance);
    }

    function emergencyWithdrawNativeToken() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "no native token to withdraw");
        payable(owner()).transfer(balance);
    }
}
