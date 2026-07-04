// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAlloyLaunchpad {
    struct CoinInfo {
        address addr;
        address backingStock;
        string name;
        string symbol;
        string stockTicker;
        uint256 feesAccrued;
        uint256 totalDividendsPaid;
        uint256 launchTimestamp;
        address creator;
    }

    function coinCount() external view returns (uint256);
    function getCoins() external view returns (address[] memory);
    function getCoin(uint256 index) external view returns (CoinInfo memory);
    function getCoinInfo(address coin) external view returns (address backingStock, uint256 feesAccrued);
    function launch(string calldata name, string calldata symbol, address stockToken) external payable returns (address);

    event CoinLaunched(address indexed coin, address indexed creator, address backingStock);
}
