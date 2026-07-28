# MetaEditor5-
Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance

## Medula EA

- **[MEDULA_FORMULAS.md](MEDULA_FORMULAS.md)** — formula specification for all 21 engines.
- **[MQL5/Experts/Medula/](MQL5/Experts/Medula/)** — modular MQL5 implementation (`Medula.mq5` + `.mqh` engine files) with install and testing instructions.
- **[MQL5/Experts/Medula_Single.mq5](MQL5/Experts/Medula_Single.mq5)** — **v2.00, the maintained build.** Single file, zero dependencies (no includes at all): copy into `MQL5/Experts/` and compile.
- **[tests/verify_medula.py](tests/verify_medula.py)** — 93-check regression suite covering every engine formula. Run with `python3 tests/verify_medula.py`.

### Why v2 exists

v1 compiled cleanly but **never opened a trade**. Its confidence score was compared to a
fixed threshold of 60, but because the engine weights sum to 1 and each score is capped at
±1, the attainable confidence on real market data peaked near 55 after the volatility and
spread penalties — the bar was mathematically unreachable. A linear spread penalty made it
worse, halving every score at a routine 15-point spread.

v2 replaces the fixed bar with a **self-calibrating** one: current conviction is ranked
against its own rolling distribution, and the EA acts when conviction sits in the top
percentile band of what the symbol actually produces. A top decile always exists on any
symbol, timeframe or volatility regime, so the arithmetic tunes itself. An absolute floor
still prevents trading noise in dead markets, and every rejected entry now logs its reason
to the journal and an on-chart panel.
