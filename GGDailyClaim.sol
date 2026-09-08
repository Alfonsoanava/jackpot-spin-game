// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Reward {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title GG Daily Claim
/// @notice A small, capped beta faucet for GG Good on Base.
/// @dev One wallet may claim once per UTC day. This does not prevent one person
///      from using multiple wallets, so fund the contract only with a limited batch.
contract GGDailyClaim {
    IERC20Reward public constant GG =
        IERC20Reward(0xb20000000000000000000097753Aa2437C490B8f);

    uint256 public constant REWARD_AMOUNT = 10 ether; // GG uses 18 decimals.
    uint256 public constant MAX_DAILY_CLAIMS = 25;

    address public owner;
    bool public paused = true;
    uint256 private unlocked = 1;

    mapping(address => uint256) public lastClaimDay;
    mapping(uint256 => uint256) public claimsByDay;

    event Claimed(address indexed player, uint256 amount, uint256 indexed day);
    event Paused(bool isPaused);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokensWithdrawn(address indexed to, uint256 amount);

    error NotOwner();
    error ContractPaused();
    error ContractCallerNotAllowed();
    error AlreadyClaimedToday();
    error DailyLimitReached();
    error InsufficientRewardBalance();
    error TokenTransferFailed();
    error InvalidAddress();
    error ReentrantCall();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (unlocked != 1) revert ReentrantCall();
        unlocked = 2;
        _;
        unlocked = 1;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function canClaim(address player) external view returns (bool) {
        uint256 day = currentDay();
        return !paused
            && player != address(0)
            && lastClaimDay[player] != day
            && claimsByDay[day] < MAX_DAILY_CLAIMS
            && GG.balanceOf(address(this)) >= REWARD_AMOUNT;
    }

    function claim() external nonReentrant {
        if (paused) revert ContractPaused();
        if (msg.sender != tx.origin) revert ContractCallerNotAllowed();

        uint256 day = currentDay();
        if (lastClaimDay[msg.sender] == day) revert AlreadyClaimedToday();
        if (claimsByDay[day] >= MAX_DAILY_CLAIMS) revert DailyLimitReached();
        if (GG.balanceOf(address(this)) < REWARD_AMOUNT) {
            revert InsufficientRewardBalance();
        }

        lastClaimDay[msg.sender] = day;
        claimsByDay[day] += 1;

        if (!GG.transfer(msg.sender, REWARD_AMOUNT)) revert TokenTransferFailed();
        emit Claimed(msg.sender, REWARD_AMOUNT, day);
    }

    function setPaused(bool isPaused) external onlyOwner {
        paused = isPaused;
        emit Paused(isPaused);
    }

    function withdrawTokens(address to, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (to == address(0)) revert InvalidAddress();
        if (!GG.transfer(to, amount)) revert TokenTransferFailed();
        emit TokensWithdrawn(to, amount);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
