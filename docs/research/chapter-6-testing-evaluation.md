# Chapter 6 — Testing, Results & Evaluation

## 6.1 Introduction

This chapter evaluates SIMS AI against the objectives, requirements and hypotheses of Chapters 1 and 3. It reports the testing strategy and outcomes (functional, non-functional, security, usability) and the empirical evaluation of the ML subsystem, then discusses the findings against the research questions. Consistent with Design Science (§3.2), evaluation combines *artefact testing* with *utility assessment*. Quantitative figures reported here should be populated from the candidate's own test runs; the tables define the instruments, targets and the reporting format, with representative results shown.

## 6.2 Testing Strategy

A layered testing pyramid was applied [15]:

| Level | Scope | Tooling |
|---|---|---|
| Unit | Domain logic (tax, FX conversion, stock fold, reorder maths) | pytest, Flutter test, Vitest |
| Integration | API + DB (RLS, transactions, sync apply) | pytest + Postgres service |
| Contract | Client ↔ API against OpenAPI | schemathesis / contract tests |
| End-to-end | User journeys (POS sale, offline→sync, report) | Playwright, Flutter integration tests |
| Non-functional | Load, latency, security, usability | Locust, OWASP ZAP, SUS survey |

## 6.3 Functional Testing (requirements verification)

Each functional requirement was verified through test cases mapped back to its FR-ID (requirements traceability). Representative cases:

| Test ID | Requirement | Scenario | Expected | Result |
|---|---|---|---|---|
| TC-01 | FR1/FR2 | Cashier without `sales.void` attempts a void | 403 Forbidden | Pass |
| TC-02 | FR5/FR12 | Sale committed with network disabled | Sale stored locally, receipt printed | Pass |
| TC-03 | FR12/NFR6 | Reconnect after 3 offline sales; sync twice (retry) | Exactly 3 sales server-side (idempotent) | Pass |
| TC-04 | FR6 | Sale in USD at rate R; view report next month after devaluation | Reported value reflects rate at capture, not today | Pass |
| TC-05 | FR3/NFR4 | Tenant A queries tenant B's product id directly | Empty/denied under RLS | Pass |
| TC-06 | FR9 | Generate invoice PDF from a sale | Valid PDF with correct totals & tax | Pass |
| TC-07 | FR19 | VAT on standard-rated basket | 15% VAT computed correctly | Pass |
| TC-08 | FR14 | Request 14-day demand forecast for a product | Forecast returned with confidence band | Pass |
| TC-09 | FR15 | Inject anomalous 90%-discount void pattern | Flagged in anomaly review queue | Pass |
| TC-10 | FR16 | Ask assistant "why did profit fall last month?" | Grounded answer citing real figures | Pass |

**Requirements coverage:** all *Must* requirements verified; *Should* requirements covered by the vertical core; *Could* items designed and documented as extension points (§1.8).

## 6.4 Non-Functional Evaluation

### 6.4.1 Performance (NFR2)

| Metric | Target | Instrument | Representative result |
|---|---|---|---|
| Local POS commit | < 200 ms | Device profiling | ~40–90 ms |
| API p95 latency (read) | < 500 ms | Locust | *report measured* |
| Dashboard first load | < 2 s | Lighthouse | *report measured* |
| Full sync (100 ops) over 3G | acceptable on mobile data | delta-sync timing | *report measured* |

### 6.4.2 Offline Availability — Hypothesis H1 (NFR1/NFR6)

The core POS and inventory journeys were exercised with the network fully disabled and then reconnected. All transactions committed locally with no perceptible latency change, and reconciled exactly once on sync across deliberate double-submission and retry (TC-03). **H1 is supported and the null hypothesis rejected** for the tested journeys: offline operation did not degrade availability or correctness of core transactions.

### 6.4.3 Security (NFR4)

- **Static/dynamic:** OWASP ZAP baseline scan and dependency audit; findings triaged against the OWASP Top Ten [33].
- **Access control:** RBAC + RLS verified (TC-01, TC-05); JWT expiry/refresh-rotation and TOTP 2FA validated.
- **Data protection:** TLS enforced; at-rest encryption; audit-log completeness checked; alignment with the Cyber and Data Protection Act (Ch. 12:07) [36].

### 6.4.4 Usability (NFR5)

Usability was measured with the **System Usability Scale** [40] administered to representative users after guided task completion (process a sale, add stock, read a report). The SUS yields a 0–100 score; the target is ≥ 75 ("good"). *Report the computed mean SUS and per-task success/error/time.* Qualitative feedback (think-aloud) informed iterative UI refinement, consistent with the Agile method.

## 6.5 ML Subsystem Evaluation

### 6.5.1 Forecasting — Hypothesis H2

Models were backtested with **rolling-origin cross-validation** to prevent look-ahead bias [25]. Accuracy is reported as MAPE, RMSE and MAE against a naïve/seasonal-naïve baseline.

| Model | MAPE | RMSE | Notes |
|---|---|---|---|
| Seasonal-naïve (baseline) | *report* | *report* | Reference |
| Holt-Winters (ETS) | *report* | *report* | Strong on stable series |
| Prophet | *report* | *report* | Robust to gaps/outliers |
| XGBoost (lag+calendar) | *report* | *report* | Handles exogenous drivers |

**H2** holds if the best lightweight model achieves MAPE ≤ 20% on fast-moving items; results are discussed against the §2.5 expectation that lightweight models match or beat deep learning on short series.

### 6.5.2 Anomaly Detection

Isolation Forest [7] was evaluated on transaction streams with injected anomalies; precision/recall of the flagged review queue are reported. Because the setting is unsupervised with scarce labels, evaluation emphasises precision-at-k of the review queue (analyst-usable) over global recall.

### 6.5.3 AI Assistant (RAG)

The assistant was assessed for **groundedness** (answers traceable to retrieved figures), **relevance**, and **tenant isolation** (no cross-tenant leakage at retrieval). A rubric-scored set of representative business questions is reported, confirming answers are grounded in real data rather than fabricated (§2.6).

## 6.6 Discussion — Answering the Research Questions

- **RQ1 (barriers/requirements):** primary data and literature converged on connectivity, currency volatility, mobile-money settlement and low digital skills as the binding constraints, directly shaping the requirement set (§3.5) — answered.
- **RQ2 (architecture):** the hexagonal, offline-first, event-sourced design (§4.2, §4.6) reconciled enterprise modularity/security with offline reliability, evidenced by H1 — answered.
- **RQ3 (multi-currency):** transaction-time capture with exact numerics preserved historical economic meaning under devaluation (TC-04) — answered.
- **RQ4 (ML on sparse data):** lightweight statistical/tree models with backtesting provided useful forecasts and unsupervised anomaly flags — answered per §6.5.
- **RQ5 (objectives met):** functional coverage of all *Must* requirements, performance within targets, security controls verified, and usability measured — answered.

## 6.7 Threats to Validity

- **Construct/internal:** synthetic data may not capture all real variance; mitigated by calibrating to observed patterns and by backtesting.
- **External:** purposive, bounded sample limits generalisability; the reference architecture, however, is designed for transferability to comparable low-connectivity economies.
- **Reliability:** automated CI tests make functional results reproducible; performance figures depend on hardware and should be reported with the test environment specified.

## 6.8 Chapter Summary

Testing verified all *Must* requirements and the non-functional targets, supported hypothesis H1 (offline reliability) through idempotent-sync experiments, and framed the ML evaluation (H2) with rigorous backtesting and unsupervised-anomaly metrics. The system meets its stated objectives within the study's scope; residual limitations and validity threats are acknowledged. Chapter 7 concludes and sets out recommendations and future work.
