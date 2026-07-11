# Changelog

## v1.0.0 — 2026-07-09
- Mainnet deployment on Robinhood Chain (chainId 4663)
- AlloyLaunchpad: `0x927750E6EebAD299EFDb88f37F830BAD27b0657e`
- AlloyKeeper deployed and active
- 94 tokenized stocks supported at launch

## v0.9.0 — 2026-07-05
- Audit complete — no critical/high findings
- Gas optimizations: viaIR, runs=200
- AlloyKeeper interval configurable (min 10 min)
- DistributionMath library extracted and fuzz-tested

## v0.8.0 — 2026-07-03
- AlloyIndex: basket index of tokenized stocks
- Walk-forward backtesting of distribution math
- Added `distributeAll()` for keeper batch runs
- Integration tests on Robinhood Chain testnet

## v0.7.0 — 2026-06-28
- Mean-reversion fee sweep: converts pool fees to stock via spot swap
- Slippage protection on keeper swaps (max 1% deviation)
- Full test suite: 47 tests, 94% line coverage

## v0.6.0 — 2026-06-20
- AlloyMeme dividend claim gas reduced by 31% (index math refactor)
- ReentrancyGuard added to all external entry points
- Fuzz tests for DistributionMath.claimable()





