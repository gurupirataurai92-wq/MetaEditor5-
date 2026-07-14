# Chapter 7 — Conclusions & Recommendations

## 7.1 Introduction

This concluding chapter revisits the research aim and objectives, summarises the principal findings and contributions, states the study's limitations, and sets out recommendations for practice and directions for future work.

## 7.2 Summary of the Research

The study set out to design, implement and evaluate **SIMS AI**, an offline-first, AI-augmented enterprise business-management ecosystem tailored to the Zimbabwean informal and SME sector, whose digitalisation is impeded by intermittent connectivity, currency volatility, mobile-money-first payments and limited digital skills. Following a Design-Science, mixed-methods, iterative-Agile approach, the research investigated the sector's constraints and requirements (Chapter 3), designed an enterprise reference architecture (Chapter 4), implemented a demonstrable vertical core across backend, web, mobile/PWA and ML/AI surfaces (Chapter 5), and evaluated the result against functional, non-functional and contextual criteria (Chapter 6).

## 7.3 Achievement of Objectives

| Objective | Status | Evidence |
|---|---|---|
| RO1 — investigate constraints, specify requirements | Achieved | §3.4–3.5; FR/NFR tables |
| RO2 — design enterprise, offline-first reference architecture | Achieved | Chapter 4 (hexagonal, DDD, RLS, sync) |
| RO3 — implement core system across all surfaces | Achieved (vertical core) | Chapter 5; CI pipeline |
| RO4 — transaction-time multi-currency + sync design | Achieved | §4.5.2, §4.6; TC-03, TC-04 |
| RO5 — develop & evaluate ML/AI subsystem | Achieved | §4.7, §5.8, §6.5 |
| RO6 — evaluate against objectives | Achieved | Chapter 6 |

## 7.4 Key Findings

1. **Offline-first is both necessary and achievable for transactional finance.** By restricting the design to immutable, event-sourced ledgers with UUID idempotency and Lamport ordering, conflict-free reconciliation of financial data was obtained without general-purpose CRDT complexity — supporting hypothesis H1 (no degradation of core-transaction availability or correctness offline).
2. **Currency meaning must be captured at transaction time.** Persisting amount, currency and applicable exchange rate as exact numerics preserves the economic interpretation of historical records under devaluation — a property conventional ERPs lack and a concrete answer to RQ3.
3. **Lightweight ML suits informal-sector data.** Statistical and tree-based forecasters, rigorously backtested, provide practically useful forecasts on short, sparse series without deep-learning-scale data (H2), and unsupervised anomaly detection yields an analyst-usable fraud-review queue.
4. **Grounded AI is trustworthy AI.** Retrieval-augmented generation over each tenant's own data delivers natural-language business advice that is factual and auditable, while tenant-isolated retrieval upholds the security boundary.

## 7.5 Contributions

- **A reference architecture** for offline-first, multi-tenant ERP in low-connectivity, high-volatility economies (transferable design knowledge, per DSR).
- **A transaction-time multi-currency data model** robust to hyperinflationary volatility.
- **An idempotent, event-sourced synchronisation design** for correctness-critical financial data.
- **An applied, empirical account** of lightweight forecasting and RAG-based assistance on informal-business data — an under-represented context in the literature.
- **A working, documented, deployment-ready artefact** with full engineering documentation and manuals.

## 7.6 Limitations

The evaluation used a purposive sample and, in part, representative synthetic data (§1.10, §6.7); live production integrations with EcoCash, ZIPIT, PayNow and banking rails, and ZIMRA fiscalisation certification, were designed and mocked rather than certified (§1.8). Rapidly-changing currency and regulatory conditions are parameterised rather than fixed. The academic timeline bounds longitudinal adoption measurement.

## 7.7 Recommendations

**For practice / SMEs:** adopt the offline-first core first (POS, inventory, receipts) to secure immediate record-keeping and cash visibility before enabling analytics and AI; use the transaction-time currency records as the basis for building the verifiable financial history that unlocks formal credit.

**For policy:** the transaction-time, audit-logged financial records SIMS AI produces align informal enterprises with ZIMRA compliance and financial inclusion; supportive fiscalisation and open payment-API access would accelerate uptake.

**For developers extending the system:** implement the documented extension points (full payroll runs, IFRS-format statements, loyalty, deep payment/fiscalisation integrations) behind the existing ports; extract the ML inference service as load grows.

## 7.8 Future Work

- **Production payment and fiscalisation integrations** with live provider certification.
- **Federated / privacy-preserving learning** to improve forecasts across tenants without sharing raw data.
- **Voice and vernacular-language interfaces** (Shona/Ndebele) to further lower the literacy barrier.
- **Alternative-data credit scoring** built on the accumulated transaction history, in partnership with lenders.
- **Longitudinal field study** measuring real adoption, business outcomes and formalisation over 12–24 months.
- **CRDT exploration** for the small set of genuinely concurrently-edited entities, should collaborative editing expand.

## 7.9 Concluding Remarks

SIMS AI demonstrates that enterprise-grade software-engineering principles can be adapted, rather than merely imported, to serve a context that mainstream ERP has overlooked. By engineering deliberately for Zimbabwe's connectivity, currency and payment realities, and by grounding its AI in each business's own data, the system turns the informal sector's constraints into design requirements met — offering a credible path to modernised, transparent and ultimately more bankable small businesses. The reference architecture and empirical findings contribute knowledge that extends beyond a single system to the broader challenge of digitalising the informal economies of the developing world.
