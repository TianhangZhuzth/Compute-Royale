# Security

## Invariants

| # | Invariant | Enforced by |
| --- | --- | --- |
| 1 | Total supply is fixed at 1e9 and can never increase | No mint path exists after construction |
| 2 | Liquidity can never be withdrawn | LP NFT is minted to the launchpad and has no transfer-out path |
| 3 | Claims never exceed reward held | `distribute()` credits only amounts already delivered to the contract |
| 4 | No account can claim twice | `withdrawn[a]` is monotonic and subtracted from `accrued(a)` |
| 5 | Accrued rewards cannot be confiscated | `exclude()` reverts once `magPerShare != 0` |
| 6 | Fee shares always sum to 100% | `setFeeSplit` requires `drip + creator + alloy == 10_000` |
| 7 | The backing stock is immutable per coin | `reward` is `immutable` on `AlloyMeme` |
| 8 | Drips reach only real holders | Pool, launchpad and burn address are excluded from `eligibleSupply` |

## Admin scope

The launchpad owner **can**:

- set the fee split (constrained to sum to `10_000`)
- set the creation fee
- set the treasury address
- configure the `$ALLOY` token, pool fee tier, sink, and free-launch threshold

The launchpad owner **cannot**:

- mint, burn, pause, or freeze any coin
- move or seize any holder's balance
- unlock, move, or withdraw liquidity
- alter a coin's backing stock after launch
- withdraw accrued drips

`AlloyMeme` has no owner at all. Its only privileged function is `exclude()`, callable solely by the launchpad that deployed it, and only before any distribution has occurred.

## Threat model

### Fee-sweep MEV

`sweep()` swaps with `amountOutMinimum = 0`, so a sweep is sandwichable.

This is a considered trade-off. The alternative — deriving a minimum from an on-chain price — requires an oracle over intentionally thin, newly created liquidity, which is more manipulable than the swap it would protect. Swept amounts are fee-sized (a fraction of a percent of volume), which bounds the extractable value per call to a small fraction of the drip. Frequent sweeps keep each individual amount, and therefore each attack's payoff, small.

### Distribution before any holder exists

At launch, `eligibleSupply == 0`. An unguarded `distribute()` would divide by zero and revert, bricking `sweep()` for a coin that has traded but has no holders yet (all supply still in the pool). `_route` checks `eligibleSupply > 0` and reserves the drip share to the treasury for that interval instead.

### Stranded rewards

If reward tokens are delivered to a coin without a matching `distribute()` call, they are not credited to anyone and are not claimable. The protocol never does this — every swap-to-reward is immediately followed by `distribute()` with the exact amount received in the same transaction.

### Rounding

`magPerShare` truncates on each distribution, so a negligible dust remainder accumulates in the contract rather than being over-distributed. Truncation is always in the protocol's favour, which preserves invariant 3. It can never round in a way that lets claims exceed the balance.

### Reentrancy

Reward tokens are Robinhood-issued tokenized stocks, not arbitrary user-supplied contracts. `claim()` follows checks-effects-interactions: `withdrawn` is incremented before the transfer. `_route` completes all accounting before external calls where practical, and the swap router is a fixed, trusted immutable.

### Backing-token legitimacy

Anyone can pass any ERC-20 as `reward` at the contract level. The protocol does not maintain an on-chain allow-list — doing so would require a privileged curator, which conflicts with the admin-scope constraints above. Instead, the interface verifies the backing against the known set of Robinhood-issued tokenized stocks and surfaces an explicit warning when a coin is backed by a token outside that set. Integrators should perform the same check rather than assuming a coin's backing is a legitimate equity.

### Griefing exclusions

`exclude()` could in principle be used to remove an address from dividends. It is callable only by the launchpad, which calls it exactly three times during `launch()` (itself, the burn address, the pool), and is hard-rejected once `magPerShare != 0`. There is no path for the launchpad to exclude a user address, and no path to exclude anything after the first distribution.

## Audit status

The protocol is **unaudited**. The contracts are verified on Blockscout and the source is in this repository. Read them before depositing value.







