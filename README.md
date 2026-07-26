# MetaEditor5-

MQL5 Expert Advisors for MetaTrader 5 / MetaEditor 5.

## Experts

### `Experts/SupplyDemandPriceActionEA.mq5`
Pure **Supply & Demand + Price Action** EA — **uses no indicators at all**, only
raw candle (OHLC) structure.

- **Symbols:** Gold (`XAUUSD`) and `EURUSD` (symbol names are inputs so you can
  match your broker, e.g. `XAUUSD.m`, `GOLD`).
- **Timeframe:** M15 (configurable).
- **Logic (OODA loop):**
  - **Observe** – reads M15 candles via `CopyRates`, classifies each as *base*
    (consolidation) or *impulse* (explosive).
  - **Orient** – maps fresh **demand** and **supply** zones from
    Rally-Base-Rally / Drop-Base-Drop / reversal-base patterns, and reads market
    structure from swing highs/lows.
  - **Decide** – triggers only when price taps a fresh zone *and* a price-action
    confirmation candle prints (bullish/bearish engulfing, pin-bar/hammer,
    shooting-star, or strong rejection close), aligned with structure.
  - **Act** – enters at market with the stop beyond the zone's distal line and a
    configurable reward:risk take-profit; lots sized from a fixed % account risk.
- **Management:** break-even, R-based trailing stop, optional early exit when
  price runs into an opposing fresh zone.
- **Safety:** spread cap, per-symbol position cap, daily-loss halt, minimum
  equity floor, margin-aware position sizing. No DLLs, no external files.

**Install:** copy the `.mq5` file into
`<MT5 data folder>/MQL5/Experts/`, compile in MetaEditor (F7), then attach to an
M15 chart. Enable **Algo Trading**. Always validate in the Strategy Tester and
on a demo account before trading live. Adjust `GoldSymbol` / `ForexSymbol` to
match the exact symbol names your broker uses.

### `Experts/GoldPortfolioEA.mq5`
Adaptive multi-symbol, gold-anchored M1 portfolio EA (separate strategy).

---

> ⚠️ Trading is risky. These EAs are provided for educational purposes. Test
> thoroughly in the Strategy Tester and on demo before any live use.
