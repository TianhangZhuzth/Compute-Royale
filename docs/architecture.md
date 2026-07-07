# Architecture

## Design constraints

Alloy was designed against four hard constraints:

1. **No custody.** The protocol must never hold user funds beyond the atomic span of a transaction.
2. **No oracle.** Backing value is established by real swaps against real liquidity, never by a reported price.
3. **No unbounded loops.** Distribution must be constant-time regardless of holder count.
4. **No admin over balances.** The owner must be unable to mint, pause, seize, or unlock liquidity.

Every structural decision below follows from these.

## Components

| Contract | Responsibility |
| --- | --- |
| `AlloyLaunchpad` | Launches coins, seeds and locks liquidity, routes fees, holds the LP set |
| `AlloyMeme` | Fixed-supply ERC-20 with dividend accounting over a reward token |
| `IUniswap` | Minimal surface of the Uniswap V3 contracts consumed by the protocol |

The launchpad is the only privileged caller of `AlloyMeme.exclude`. Nothing else in the system has authority over a coin after launch.

## Control flow

### Launch

```
launch(name, symbol, info, reward, rewardFee, salt)
  |
  |-- resolve fee (waived if caller holds >= freeLaunchThreshold of $ALLOY)
  |-- CREATE2 deploy AlloyMeme, entire supply minted to launchpad
  |-- exclude(launchpad), exclude(DEAD)
  |-- _seed()
  |     |-- createAndInitializePoolIfNecessary(token0, token1, 1%, sqrtPriceX96)
  |     |-- exclude(pool)                  <- before liquidity moves in
  |     |-- positionManager.mint(...)      <- entire supply, single-sided
  |     '-- LP NFT retained by launchpad   <- never transferred out
  |-- burn dust left by liquidity rounding
  |-- record Meme{creator, pool, reward, rewardFee, lpId, createdAt}
  '-- emit MemeLaunched(...)
```

The exclusion ordering is load-bearing. `exclude(pool)` must execute **before** `positionManager.mint` moves the supply into the pool. Excluding an address is only permitted while `magPerShare == 0`, and the eligible-supply bookkeeping subtracts the excluded balance at the moment of exclusion. Excluding the pool while it is empty, then filling it, leaves `eligibleSupply == 0` at launch and grows it organically as buyers withdraw supply from the pool.

### Single-sided seeding

The pool is initialised at a price *below* the range in which the supply sits (or above, depending on token ordering), so the position is composed entirely of the coin and requires zero USDG from the launcher.

Token ordering is resolved at runtime because the coin address is a `CREATE2` output and may sort either side of USDG:

| Ordering | Init price | Range | Supply side |
| --- | --- | --- | --- |
| `coin < usdg` | `sqrtPriceLowX96` | `[-startTick, MAX_USABLE_TICK]` | `amount0` |
| `coin > usdg` | `sqrtPriceHighX96` | `[-MAX_USABLE_TICK, startTick]` | `amount1` |

Both `sqrtPrice` bounds are precomputed off-chain and supplied as immutables, avoiding on-chain `TickMath`.

### Sweep

```
sweep(token)
  |-- positionManager.collect(lpId) -> (amount0, amount1)
  |-- identify coin side vs USDG side by token ordering
  |-- sell coin side -> USDG                       (everything routes in dollars)
  '-- _route(token, reward, rewardFee, creator, usdgAmount)
        |-- dripUsdg  = usdg * dripBps / 10000
        |-- alloyUsdg = usdg * alloyBps / 10000
        |-- if eligibleSupply > 0:
        |     swap USDG -> reward, recipient = the AlloyMeme itself
        |     AlloyMeme.distribute(amountReceived)
        |   else:
        |     reserve to treasury            <- nobody holds yet; nothing to drip to
        |-- if $ALLOY configured: swap USDG -> $ALLOY, recipient = alloySink
        |   else: reserve to treasury
        '-- remainder -> creator
```

`sweep` is permissionless. Anyone may call it; the caller pays gas and receives nothing, so in practice a keeper runs it on a schedule. It is intentionally not incentivised on-chain: a caller reward would be extractable and would complicate the fee split's invariant.

The `eligibleSupply > 0` guard matters. Before anyone holds the coin, `distribute()` would divide by zero. Rather than revert — which would brick sweeps on a freshly launched coin — the drip share is reserved to the treasury for that interval.

## Quote asset

Coins pair against **USDG**, not the native token. This is deliberate:

- Robinhood's tokenized stocks quote against USDG. Pairing coins against USDG means collected fees are already denominated in the same asset used to buy the backing stock, so the drip path is a single hop.
- Pairing against a volatile asset would add a second swap and a second slippage event to every distribution, paid for out of holders' drip.
- Dollar-denominated pricing makes launch valuation legible.

The cost is that buyers holding the native token need routing. The interface handles this with a multi-hop `exactInput` over `WETH -> USDG -> coin`, so paying with ETH remains one transaction and one approval-free swap.

## Stack-depth note

`launch()` cannot be written with nested ternaries feeding a Uniswap `MintParams` literal. Even with `viaIR` and the optimizer enabled, the Yul stack scheduler fails with `Variable is N too deep in the stack`. The working form assigns fields onto a memory struct with straight-line `if/else` branches, and factors swaps into a `_swap` helper. This is a compiler constraint, not a style preference.


