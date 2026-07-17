# Mechanism

## Distribution

Alloy distributes a reward token (a tokenized stock) to holders of a coin, pro-rata by balance, in constant time.

Naive designs iterate holders on distribution. That is gas-unbounded and breaks past a few hundred holders. Alloy instead uses a **magnified per-share accumulator**: distribution updates a single storage slot, and each holder's entitlement is derived on read.

### State

| Symbol | Storage | Meaning |
| --- | --- | --- |
| $M$ | `magPerShare` | Cumulative reward per eligible share, magnified by $2^{128}$ |
| $S$ | `eligibleSupply` | Supply held by non-excluded addresses |
| $c_a$ | `corrections[a]` | Signed correction preserving $a$'s entitlement across balance changes |
| $w_a$ | `withdrawn[a]` | Reward already claimed by $a$ |

### Distributing

Given reward amount $A$ already delivered to the token contract:

$$M \mathrel{+}= \left\lfloor \frac{A \cdot 2^{128}}{S} \right\rfloor$$

One `SSTORE`. Cost is independent of holder count.

### Reading entitlement

$$\text{accrued}(a) = \left\lfloor \frac{M \cdot \text{balance}(a) + c_a}{2^{128}} \right\rfloor \qquad \text{claimable}(a) = \text{accrued}(a) - w_a$$

### Why corrections exist

$M \cdot \text{balance}(a)$ alone would credit a holder for distributions that happened *before* they held the tokens. The correction term cancels exactly that.

On a transfer of $v$ from $f$ to $t$, at the current accumulator $M$:

$$c_f \mathrel{+}= M \cdot v \qquad c_t \mathrel{-}= M \cdot v$$

The receiver's negative correction offsets the entitlement their new balance would otherwise imply from past distributions. The sender's positive correction preserves the entitlement they earned while holding. Both are exact — no rounding is introduced at transfer time, only at read time.

Mint (`from == 0`) and burn (`to == 0`) are the same code path with one side skipped, so supply changes stay consistent.

### Precision

The $2^{128}$ magnitude absorbs truncation. With $S \approx 10^{27}$ wei (1e9 tokens at 18 decimals) and a distribution as small as one wei of an 18-decimal stock:

$$\Delta M = \left\lfloor \frac{1 \cdot 2^{128}}{10^{27}} \right\rfloor \approx 3.4 \times 10^{11}$$

Still eleven significant digits of headroom, so dust distributions are not rounded to zero. Overflow is not a practical concern: $M$ would need roughly $10^{50}$ wei of cumulative reward to threaten a `uint256`.

### Eligible supply

$$S = \text{totalSupply} - \sum_{e \in \text{excluded}} \text{balance}(e)$$

At launch the AMM pool holds effectively the entire supply. If the pool were eligible it would absorb the overwhelming majority of every drip, and that reward would be permanently stranded — the pool has no claim path. Excluding it makes $S$ the *circulating, held* supply, which is the correct denominator: the drip belongs to people, not to the liquidity.

`eligibleSupply` is maintained incrementally in `_update`, adjusting only for the sides of a transfer that are non-excluded. It is never recomputed by iteration.

### Solvency

`distribute(A)` is only ever called with an amount that was just delivered to the contract by the swap that preceded it. Since

$$\sum_a \text{claimable}(a) \le \sum_{\text{distributions}} A \le \text{rewardBalance}$$

every claim is covered. `claim()` transfers only `claimable(msg.sender)` and increments `withdrawn`, so no account can withdraw twice.

## Launch pricing

A coin opens at a deterministic price set by `startTick`, with no external input.

Uniswap V3 prices are `token1` per `token0` in **raw** units. For an 18-decimal coin against 6-decimal USDG, the human-readable price carries a $10^{12}$ scale factor:

$$P_{\text{human}} = P_{\text{raw}} \times 10^{\,d_{\text{coin}} - d_{\text{usdg}}} = P_{\text{raw}} \times 10^{12}$$

Targeting a fully-diluted valuation $F$ over supply $N = 10^9$:

$$P_{\text{human}} = \frac{F}{N} \qquad P_{\text{raw}} = \frac{F}{N} \times 10^{-12}$$

$$\text{tick} = \left\lfloor \frac{\ln P_{\text{raw}}}{\ln 1.0001} \right\rceil_{200}$$

For $F = \$5{,}000$:

$$P_{\text{raw}} = 5 \times 10^{-18} \implies \text{tick} = \frac{\ln(5 \times 10^{-18})}{\ln 1.0001} \approx -398{,}388 \implies \texttt{startTick} = 398400$$

Rounded to the 1% tier's 200 spacing. Verifying:

$$1.0001^{-398400} \times 10^{12} \times 10^{9} \approx \$4{,}995$$

Because the tick is a pure ratio, the magnitude is symmetric under token ordering: whichever side the `CREATE2` address sorts to, $\pm\texttt{startTick}$ describes the same opening valuation, with the sign and range bounds flipped.

## Drip yield

The interface surfaces an annualised estimate, not a promise. Given cumulative dripped value $D$ over coin age $t$ seconds against a denominator $V$ (the value of held supply):

$$\text{APR} \approx \frac{D \cdot \frac{31{,}536{,}000}{t}}{V} \times 100$$

For a forward estimate from volume, where holders collectively receive 70% of the 1% fee:

$$\text{drip}_{\text{daily}} = \text{volume}_{\text{daily}} \times 0.01 \times 0.70$$

and an individual's share is their portion of held supply. Both are estimates: realised drips depend entirely on actual volume and the holder set at distribution time.









