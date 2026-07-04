// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AlloyIndex is ERC20, Ownable {
    struct Constituent {
        address stockToken;
        uint256 weight;
        string ticker;
    }

    Constituent[] public constituents;
    mapping(address => uint256) public holderIndex;
    uint256 public globalIndex;
    uint256 internal constant PRECISION = 1e18;

    event DividendDistributed(uint256 amount);
    event DividendClaimed(address indexed holder, uint256 amount);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    function addConstituent(address stockToken, uint256 weight, string calldata ticker) external onlyOwner {
        constituents.push(Constituent(stockToken, weight, ticker));
    }

    function pendingDividends(address holder) external view returns (uint256) {
        return (balanceOf(holder) * (globalIndex - holderIndex[holder])) / PRECISION;
    }

    function claimDividends() external {
        uint256 pending = (balanceOf(msg.sender) * (globalIndex - holderIndex[msg.sender])) / PRECISION;
        holderIndex[msg.sender] = globalIndex;
        if (pending > 0) emit DividendClaimed(msg.sender, pending);
    }

    function distribute(uint256 amount) external onlyOwner {
        if (totalSupply() == 0) return;
        globalIndex += (amount * PRECISION) / totalSupply();
        emit DividendDistributed(amount);
    }
}
