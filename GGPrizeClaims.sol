// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Prize {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title GG Prize Claims
/// @notice Owner-approved GG Good prize claims on Base.
/// @dev Keep paused and unfunded until testing is complete.
contract GGPrizeClaims {
    IERC20Prize public constant GG =
        IERC20Prize(0xb20000000000000000000097753Aa2437C490B8f);

    uint256 public constant TEN_GG = 10 ether;
    uint256 public constant TWENTY_FIVE_GG = 25 ether;
    uint256 public constant FIFTY_GG = 50 ether;
    uint256 public constant MAX_DAILY_CLAIMS = 25;

    struct PrizeClaim {
        address player;
        uint256 amount;
        uint256 expiresAt;
        bool claimed;
        bool cancelled;
    }

    address public owner;
    bool public paused = true;
    uint256 private unlocked = 1;

    mapping(bytes32 => PrizeClaim) public prizeClaims;
    mapping(address => uint256) public lastClaimDay;
    mapping(uint256 => uint256) public claimsByDay;

    event PrizeApproved(
        bytes32 indexed claimId,
        address indexed player,
        uint256 amount,
        uint256 expiresAt
    );

    event PrizeClaimed(
        bytes32 indexed claimId,
        address indexed player,
        uint256 amount
    );

    event PrizeCancelled(bytes32 indexed claimId);
    event Paused(bool isPaused);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event TokensWithdrawn(address indexed to, uint256 amount);

    error NotOwner();
    error ContractPaused();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidClaim();
    error ClaimAlreadyExists();
    error ClaimAlreadyUsed();
    error ClaimCancelled();
    error ClaimExpired();
    error WrongWallet();
    error AlreadyClaimedToday();
    error DailyLimitReached();
    error InsufficientRewardBalance();
    error TokenTransferFailed();
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

    function validAmount(uint256 amount) public pure returns (bool) {
        return (
            amount == TEN_GG ||
            amount == TWENTY_FIVE_GG ||
            amount == FIFTY_GG
        );
    }

    function approvePrize(
        bytes32 claimId,
        address player,
        uint256 amount,
        uint256 expiresAt
    ) external onlyOwner {
        if (paused) revert ContractPaused();
        if (claimId == bytes32(0)) revert InvalidClaim();
        if (player == address(0)) revert InvalidAddress();
        if (!validAmount(amount)) revert InvalidAmount();
        if (expiresAt <= block.timestamp) revert ClaimExpired();
        if (prizeClaims[claimId].player != address(0)) {
            revert ClaimAlreadyExists();
        }

        prizeClaims[claimId] = PrizeClaim({
            player: player,
            amount: amount,
            expiresAt: expiresAt,
            claimed: false,
            cancelled: false
        });

        emit PrizeApproved(claimId, player, amount, expiresAt);
    }

    function canClaim(bytes32 claimId, address player)
        external
        view
        returns (bool)
    {
        PrizeClaim memory prize = prizeClaims[claimId];
        uint256 day = currentDay();

        return (
            !paused &&
            prize.player == player &&
            player != address(0) &&
            !prize.claimed &&
            !prize.cancelled &&
            block.timestamp <= prize.expiresAt &&
            lastClaimDay[player] != day &&
            claimsByDay[day] < MAX_DAILY_CLAIMS &&
            GG.balanceOf(address(this)) >= prize.amount
        );
    }

    function claimPrize(bytes32 claimId) external nonReentrant {
        if (paused) revert ContractPaused();

        PrizeClaim storage prize = prizeClaims[claimId];

        if (prize.player == address(0)) revert InvalidClaim();
        if (prize.claimed) revert ClaimAlreadyUsed();
        if (prize.cancelled) revert ClaimCancelled();
        if (block.timestamp > prize.expiresAt) revert ClaimExpired();
        if (msg.sender != prize.player) revert WrongWallet();

        uint256 day = currentDay();

        if (lastClaimDay[msg.sender] == day) {
            revert AlreadyClaimedToday();
        }

        if (claimsByDay[day] >= MAX_DAILY_CLAIMS) {
            revert DailyLimitReached();
        }

        if (GG.balanceOf(address(this)) < prize.amount) {
            revert InsufficientRewardBalance();
        }

        prize.claimed = true;
        lastClaimDay[msg.sender] = day;
        claimsByDay[day] += 1;

        _safeTransfer(msg.sender, prize.amount);

        emit PrizeClaimed(claimId, msg.sender, prize.amount);
    }

    function cancelPrize(bytes32 claimId) external onlyOwner {
        PrizeClaim storage prize = prizeClaims[claimId];

        if (prize.player == address(0)) revert InvalidClaim();
        if (prize.claimed) revert ClaimAlreadyUsed();

        prize.cancelled = true;
        emit PrizeCancelled(claimId);
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

        _safeTransfer(to, amount);
        emit TokensWithdrawn(to, amount);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();

        address previousOwner = owner;
        owner = newOwner;

        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function _safeTransfer(address to, uint256 amount) private {
        (bool success, bytes memory data) = address(GG).call(
            abi.encodeWithSelector(IERC20Prize.transfer.selector, to, amount)
        );

        if (
            !success ||
            (data.length != 0 && !abi.decode(data, (bool)))
        ) {
            revert TokenTransferFailed();
        }
    }
}
