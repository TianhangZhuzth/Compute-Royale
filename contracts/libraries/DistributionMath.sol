// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library DistributionMath {
    uint256 internal constant PRECISION = 1e18;

    function computeIncrement(uint256 totalFees, uint256 totalSupply) internal pure returns (uint256) {
        if (totalSupply == 0) return 0;
        return (totalFees * PRECISION) / totalSupply;
    }

    function claimable(uint256 balance, uint256 globalIndex, uint256 holderIndex) internal pure returns (uint256) {
        if (globalIndex <= holderIndex) return 0;
        return (balance * (globalIndex - holderIndex)) / PRECISION;
    }

    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "overflow");
        return c;
    }
}








