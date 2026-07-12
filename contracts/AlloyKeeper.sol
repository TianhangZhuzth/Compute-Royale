// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAlloyLaunchpadKeeper {
    function getCoins() external view returns (address[] memory);
    function getCoinInfo(address coin) external view returns (address backingStock, uint256 feesAccrued);
}

interface IAlloyMemeKeeper {
    function distribute(uint256 amount) external;
}

contract AlloyKeeper is Ownable, ReentrancyGuard {
    IAlloyLaunchpadKeeper public immutable launchpad;
    uint256 public interval = 3600;
    uint256 public lastRun;

    event Distributed(address indexed coin, uint256 amount);
    event IntervalUpdated(uint256 newInterval);

    constructor(address _launchpad) Ownable(msg.sender) {
        launchpad = IAlloyLaunchpadKeeper(_launchpad);
    }

    function getPendingCoins() external view returns (address[] memory pending) {
        address[] memory all = launchpad.getCoins();
        uint256 count;
        for (uint256 i; i < all.length; ++i) {
            (, uint256 fees) = launchpad.getCoinInfo(all[i]);
            if (fees > 0) ++count;
        }
        pending = new address[](count);
        uint256 j;
        for (uint256 i; i < all.length; ++i) {
            (, uint256 fees) = launchpad.getCoinInfo(all[i]);
            if (fees > 0) pending[j++] = all[i];
        }
    }

    function distribute(address coin) external nonReentrant {
        (, uint256 fees) = launchpad.getCoinInfo(coin);
        require(fees > 0, "no fees");
        IAlloyMemeKeeper(coin).distribute(fees);
        emit Distributed(coin, fees);
    }

    function distributeAll() external nonReentrant {
        require(block.timestamp >= lastRun + interval, "too soon");
        lastRun = block.timestamp;
        address[] memory all = launchpad.getCoins();
        for (uint256 i; i < all.length; ++i) {
            (, uint256 fees) = launchpad.getCoinInfo(all[i]);
            if (fees > 0) {
                try IAlloyMemeKeeper(all[i]).distribute(fees) {
                    emit Distributed(all[i], fees);
                } catch {}
            }
        }
    }

    function setInterval(uint256 _interval) external onlyOwner {
        require(_interval >= 600, "min 10 min");
        interval = _interval;
        emit IntervalUpdated(_interval);
    }
}






