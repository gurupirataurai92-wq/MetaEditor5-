# IAX v7.0 "GODMODE+ / OODA" — Technical Notes

EA file: `MQL5/Experts/IAX_v7/IAX_v7_GODMODE_PLUS_OODA.mq5`.

This is the v6 GODMODE engine restructured as an **explicit OODA loop** (Observe → Orient → Decide → Act). Every formula — factors, regime classifier, confidence, geometry, governors, learning — is identical to v6 and documented in [`IAX_v6_TECHNICAL.md`](IAX_v6_TECHNICAL.md); this document covers only what v7 changes. **No profit is promised.**

## 1. The OODA mapping

Every tick is one OODA **cycle**:

| Phase | Function(s) | What happens |
|---|---|---|
| **Observe** | inline in `OnTick()` | Tick-delta buffer, session VWAP, hourly/daily counters, equity governors, feed-health heartbeat, new-bar detection. Pure data ingestion — no judgement. |
| **Orient** | `OODA_Orient()` | The 9 factor votes fused into buy/sell probabilities over the active weight pool, then regime, session quality, ignition/exhaustion, and the confidence score. Returns the implied direction. Adaptive learning is the slow half of Orient: it re-orients the factor weights themselves after each closed basket. |
| **Decide** | `OODA_Decide()` | One explicit, logged decision per cycle: `NONE`, `ENTER_LONG`, `ENTER_SHORT`, or `BLOCKED` — passed through the idempotency guard (one entry per bar), edge gate, confidence gate, and the full v6 governor stack. Every non-entry outcome carries a human-readable reason string. |
| **Act** | `OODA_Act()` + the standing management block | Entry execution via the v6 entry engine, plus the standing Act layer (pending-order expiry, R-multiple/basket management, swing module, protective-stop sweep, flip exits) which runs every cycle whether or not a new decision fired. |

Orient→Decide→Act runs on every **closed signal bar**, exactly like v6 — plus optionally mid-bar under tempo (below).

## 2. What's new vs v6 ("the +")

- **Per-phase telemetry**: microsecond timings for Observe / Orient / Decide / Act are accumulated per full loop and reported on the dashboard and in the end-of-run report (`InpOODALogPhaseTimings`). If the loop is slow, you now know which phase.
- **Decision ledger**: the last `InpOODALedgerSize` (default 6) decisions — cycle number, time, decision, reason — are shown newest-first on the dashboard. The answer to "why didn't it trade just now?" is on screen, not buried in the log.
- **Tempo (`InpOODATempoSec`)**: OODA doctrine says operate inside the opponent's decision cycle. With tempo > 0, the EA re-runs Orient→Decide→Act mid-bar every N seconds — but **only** in fast regimes (`BREAKOUT_UP/DOWN`, `VOL_EXPANSION`) where waiting for bar close forfeits the move. Guard rails:
  - **One entry per bar**, enforced by an idempotency guard in Decide — tempo can catch a breakout later in a bar it hadn't entered, never pyramid the same bar.
  - **Exits remain bar-confirmed** regardless of tempo (defect rule 9: intrabar flips churn noise into realized losses).
  - The chase guard still applies, so tempo cannot buy the top of a bar that already ran.
  - **Default is 0 (off)** — bar-close-only, identical cadence to v6. Treat tempo as a Stage-5 experiment, and backtest it against tempo=0 before trusting it.
- **Separate identity**: magic 770001 (vs v6's 660001), `IAX7_`-prefixed GlobalVariables, state file, and journal — v6 and v7 can run side by side on the same account without touching each other's positions or learned state.

## 3. New inputs

| Input | Default | Meaning |
|---|---|---|
| `InpOODATempoSec` | 0 | Mid-bar re-orientation cadence in seconds, fast regimes only. 0 = bar-close only (safest). |
| `InpOODALedgerSize` | 6 | Decision-ledger rows kept for the dashboard. |
| `InpOODALogPhaseTimings` | true | Include per-phase timing averages in the end-of-run report. |

Everything else — profiles, factors, geometry, governors, learning, validation stages, Stage-1 self-test — is unchanged from v6; tune it per the v6 doc's guide. If you enable tempo, treat it as one of your 3–5 optimisation parameters and validate on a disjoint date range like everything else.

## 4. Status

Like v6, this build has **not** been compiled in MetaEditor or backtested here — compile it, run the Stage-1 lifecycle self-test in the Strategy Tester, and clear the v6 doc's Grade-A acceptance criteria before any live use.
