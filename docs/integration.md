# Integration Guide

## Reading coin data

```solidity
address[] memory coins = IAlloyLaunchpad(LAUNCHPAD).getCoins();
```

Each coin exposes:

```solidity
function backingStock() external view returns (address);
function pendingDividends(address holder) external view returns (uint256);
function claimDividends() external;
```

## Triggering distributions

```solidity
IAlloyKeeper(KEEPER).distribute(coinAddress);
IAlloyKeeper(KEEPER).distributeAll();
```

## Token metadata API

```
GET https://alloy.fund/api/coins
GET https://alloy.fund/api/coins/{address}
GET https://alloy.fund/api/coins/{address}/dividends/{holder}
```

CORS-open, no key required.
