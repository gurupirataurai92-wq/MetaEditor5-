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
  - **HTF order-block nesting** — an M15 zone must sit inside a same-type zone on
    a higher timeframe (default H1), so entries align with higher-timeframe
    supply/demand (hard filter, or a confluence bonus — your choice).
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

### `Presets/` — starter parameter sets (`.set`)
Ready-to-load presets for the Strategy Tester / EA Inputs tab:

| File | Trades | Notes |
|------|--------|-------|
| `SupplyDemandEA_Combined.set` | Gold **and** EURUSD in one instance | Balanced defaults, lower risk (0.5%) since two symbols run together. |
| `SupplyDemandEA_XAUUSD.set` | Gold only (`ForexSymbol` empty) | Tuned for gold's volatility — stronger impulse, wider tolerance. |
| `SupplyDemandEA_EURUSD.set` | EURUSD only (`GoldSymbol` empty) | Tighter zones, larger runner target (3.5R). |

**How to use:** copy the `.set` files into
`<MT5 data folder>/MQL5/Presets/`, then in the Strategy Tester (or the EA's
Inputs tab) click **Load** and pick one. To run Gold and EURUSD as *separate*
chart instances, load each single-symbol preset on its own M15 chart — they use
different `MagicBase` values so their trades never collide. These are
**starting points**, not optimised settings — run the tester's optimiser over
`MinConfluenceScore`, `RiskPercent`, `TP2_R`, and the session hours per symbol.

### `Experts/GoldPortfolioEA.mq5`
Adaptive multi-symbol, gold-anchored M1 portfolio EA (separate strategy).

---

> ⚠️ **Reality check.** No EA can guarantee profit, and none of these reproduce
> what a bank's trading desk actually does (order flow, low-latency execution,
> balance-sheet advantages). This EA encodes a disciplined, institutional-style
> *methodology* — it still needs to be optimised and forward-tested per broker
> and symbol. Test thoroughly in the Strategy Tester and on a demo account
> before risking real money. Past performance never guarantees future results.
