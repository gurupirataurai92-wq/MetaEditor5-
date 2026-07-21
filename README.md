# MetaEditor5-

Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance

## IAX v6.0 "GODMODE" — Institutional Adaptive XAUUSD EA

- EA: [`MQL5/Experts/IAX_v6/IAX_v6_GODMODE.mq5`](MQL5/Experts/IAX_v6/IAX_v6_GODMODE.mq5)
- Docs: [`docs/IAX_v6_TECHNICAL.md`](docs/IAX_v6_TECHNICAL.md) — every formula, all design assumptions, parameter tuning guide, staged testing procedure.

## IAX v7.0 "GODMODE+ / OODA"

- EA: [`MQL5/Experts/IAX_v7/IAX_v7_GODMODE_PLUS_OODA.mq5`](MQL5/Experts/IAX_v7/IAX_v7_GODMODE_PLUS_OODA.mq5)
- Docs: [`docs/IAX_v7_OODA.md`](docs/IAX_v7_OODA.md) — what changed vs v6 (shared formulas stay documented in the v6 doc).

The v6 engine restructured as an explicit Observe→Orient→Decide→Act loop: per-phase microsecond telemetry, an on-chart decision ledger (last N decisions with reasons), and an optional intra-bar "tempo" mode for breakout/vol-expansion regimes (off by default; exits stay bar-confirmed). Separate magic number and persisted state, so v6 and v7 can run side by side.

v7.1 adds the **pattern-arithmetic layer**: a 60-bucket per-pattern expectancy learner (suppresses proven-losing patterns, sizes up proven winners), a learned hour-of-day volatility profile that scales TP/SL to what each hour of the gold day statistically delivers, a serial-correlation bias that tilts confidence toward continuation signals in trending tape and reversal signals in alternating tape, and round-number TP snapping (take profit in front of .00/.50 walls, not through them).

Built from `MASTER_PROMPT_v6_GODMODE.md`: a 9-factor weighted decision engine, three-mode entry engine with laddered burst entries, regime-aware geometry, R-multiple + basket-group trade management, a separate swing module, a layered governor stack, online adaptive factor-weight learning, and full ops/verification logging (nothing fails silently). No profit is promised — read the technical doc's economic-honesty section before trading anything but a demo account.

This build has not yet been compiled in MetaEditor or backtested — do that first (Stage 1 lifecycle self-test in the Strategy Tester) before anything else.
