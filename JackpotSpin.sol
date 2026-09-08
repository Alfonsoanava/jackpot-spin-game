// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract JackpotSpin {
    address public owner;
    uint256 public nextSpinId = 1;
    uint256 public constant SPIN_COOLDOWN = 1 days;

    enum Prize {
        TenTokens,
        NFTReward,
        TwentyFiveTokens,
        TryAgain,
        FiftyTokens,
        BonusSpin
    }

    struct Spin {
        address player;
        uint256 requestedAt;
        Prize prize;
        bool resolved;
    }

    mapping(address => uint256) public lastSpinTime;
    mapping(address => uint256) public bonusSpins;
    mapping(uint256 => Spin) public spins;

    event SpinRequested(
        uint256 indexed spinId,
        address indexed player
    );

    event SpinResolved(
        uint256 indexed spinId,
        address indexed player,
        Prize prize
    );

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Owner only");
        _;
    }

    function canSpin(address player) public view returns (bool) {
        return bonusSpins[player] > 0 ||
            block.timestamp >= lastSpinTime[player] + SPIN_COOLDOWN;
    }

    function requestSpin() external returns (uint256 spinId) {
        require(canSpin(msg.sender), "Come back after 24 hours");

        if (bonusSpins[msg.sender] > 0) {
            bonusSpins[msg.sender] -= 1;
        } else {
            lastSpinTime[msg.sender] = block.timestamp;
        }

        spinId = nextSpinId++;

        spins[spinId] = Spin({
            player: msg.sender,
            requestedAt: block.timestamp,
            prize: Prize.TryAgain,
            resolved: false
        });

        emit SpinRequested(spinId, msg.sender);
    }

    function resolveSpin(
        uint256 spinId,
        Prize prize
    ) external onlyOwner {
        Spin storage playerSpin = spins[spinId];

        require(playerSpin.player != address(0), "Spin not found");
        require(!playerSpin.resolved, "Spin already resolved");

        playerSpin.prize = prize;
        playerSpin.resolved = true;

        if (prize == Prize.BonusSpin) {
            bonusSpins[playerSpin.player] += 1;
        }

        emit SpinResolved(spinId, playerSpin.player, prize);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        owner = newOwner;
    }
}
