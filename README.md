# MetaEditor5-
Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance

## Experts

### `Experts/GoldPortfolioEA.mq5`
Gold-anchored multi-symbol M1 portfolio EA with volatility ranking, a native
MQL5 neural-net filter, SQLite trade logging and tiered risk sizing.

### `Experts/GoldPriceActionEA.mq5`
Gold EA driven by **raw price action only** — no indicators, no indicator
handles, no supply/demand or order-block zones, no DLLs, no external files.
Everything is read directly from OHLC.

**How it reads the market**
- **Swing structure:** fractal swing highs/lows (`InpSwingStrength` bars either
  side). A swing only becomes usable once the bars after it have printed, so the
  engine never sees a level before the market could have.
- **Break of structure:** a candle *closing* through the last confirmed swing
  sets the bias bullish or bearish and anchors the impulse leg.
- **Candlestick behaviour:** engulfing, rejection/pin bars and inside-bar
  breakouts, plus a close-strength test (where the close sits inside the
  candle's range).
- **Raw range filter:** the mean high-low range of the last `InpRangeLookback`
  candles filters dead bars and climax bars, and sets the automatic spread
  ceiling. It is plain arithmetic on candle ranges, not an indicator buffer.

**Entries** (either model, both toggleable)
1. *Breakout* — the break-of-structure candle itself, when it closes strong.
2. *Pullback* — after a break, price retraces `InpMinPullbackPct`–`InpMaxPullbackPct`
   of the impulse leg while the leg origin holds, then an engulfing/pin/inside-bar
   confirmation prints in the direction of structure.

**Exits** (all price action)
- Stop behind the signal candle / last swing, offset by a fraction of the
  average candle range.
- Optional fixed take profit in R, breakeven at `InpBreakevenR`, partial close at
  `InpPartialR`.
- Trailing behind confirmed swings (`TRAIL_STRUCTURE`) or behind the last N
  candles (`TRAIL_CANDLE`).
- Structure flip against the position, an opposing rejection/engulfing candle,
  and a time stop for trades that never developed.

**Guards:** per-trade % risk sizing from the stop distance, free-margin cap,
spread ceiling, optional session window, max trades per day, daily loss limit,
and a minimum account balance. One position at a time.

Per-trade state (the 1R reference and the management flags) is kept in terminal
global variables so a restart or recompile does not orphan an open trade.

**Install:** copy the `.mq5` file into `MQL5/Experts`, compile in MetaEditor,
attach to a XAUUSD chart (default working timeframe M15).
