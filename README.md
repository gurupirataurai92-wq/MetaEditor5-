# MetaEditor5-

MQL5 Expert Advisors for MetaTrader 5 / MetaEditor 5.

## Experts

### `Experts/SupplyDemandPriceActionEA.mq5`  (v2.00 — Smart-Money-Concepts)
Supply & Demand / **Smart-Money-Concepts** EA — **uses no indicators at all**,
only raw candle (OHLC) structure. Instead of blindly buying every demand zone,
v2 only trades when several independent factors line up (a *confluence score*).

- **Symbols:** Gold (`XAUUSD`) and `EURUSD` — names are inputs so you can match
  your broker (e.g. `XAUUSD.m`, `GOLD`).
- **Timeframes:** M15 entry, **H4 bias**, **H1 structure** (all configurable).
- **Edge stack (confluence, minimum score required to trade):**
  - **Higher-timeframe bias** — only longs when H4 structure is up, shorts when
    down; plus a **premium/discount** filter (buy only in the lower half of the
    H4 range, sell only in the upper half).
  - **Liquidity sweep / stop-hunt** — waits for price to grab liquidity beyond a
    prior swing and reclaim it *before* entering.
  - **Break of Structure (BOS/CHoCH)** — momentum shift confirmation.
  - **Order block + Fair Value Gap** — zone tightened to the origin candle for a
    smaller stop; imbalance in the impulse adds confluence.
  - **Price-action confirmation** — engulfing, pin-bar/hammer, shooting-star, or
    strong rejection close.
  - **Volatility filter** — skips dead ranges and abnormal news spikes (measured
    from candle ranges, no ATR indicator).
- **Management:** partial take-profit at TP1, break-even, and a **swing-based
  (structure) trailing stop**; TP2 runner target.
- **Safety / circuit breakers:** session filter (London/NY, GMT), per-symbol &
  total position caps, daily trade cap, **consecutive-loss cooldown**, daily-loss
  halt, spread cap, margin-aware sizing. No DLLs, no external files.

Every gate is an input, so you can loosen or tighten the strategy and run the
MT5 **Strategy Tester optimiser** over the thresholds (`MinConfluenceScore`,
`RiskPercent`, `TP2_R`, session hours, etc.) to fit each symbol.

**Install:** copy the `.mq5` file into `<MT5 data folder>/MQL5/Experts/`,
compile in MetaEditor (F7), then attach to an M15 chart with **Algo Trading**
enabled. Adjust `GoldSymbol` / `ForexSymbol` to your broker's exact symbol
names. **Always** run the Strategy Tester and a demo account first — see the
note below.

### `Experts/GoldPortfolioEA.mq5`
Adaptive multi-symbol, gold-anchored M1 portfolio EA (separate strategy).

---

> ⚠️ **Reality check.** No EA can guarantee profit, and none of these reproduce
> what a bank's trading desk actually does (order flow, low-latency execution,
> balance-sheet advantages). This EA encodes a disciplined, institutional-style
> *methodology* — it still needs to be optimised and forward-tested per broker
> and symbol. Test thoroughly in the Strategy Tester and on a demo account
> before risking real money. Past performance never guarantees future results.
