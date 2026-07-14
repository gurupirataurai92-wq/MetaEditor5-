# Chapter 2 — Literature Review

## 2.1 Introduction

This chapter surveys the scholarly and technical literature underpinning SIMS AI across five themes: (1) the informal economy and SME digitalisation, particularly in sub-Saharan Africa and Zimbabwe; (2) enterprise architecture and ERP systems; (3) offline-first and local-first application architectures with data synchronisation; (4) machine-learning approaches to demand forecasting, anomaly detection and recommendation; and (5) applied AI, including large language models and retrieval-augmented generation. The review identifies the gap that this research addresses and justifies the design choices developed in later chapters.

## 2.2 The Informal Economy and SME Digitalisation

The informal economy is a defining feature of developing-country labour markets. The International Labour Organization characterises it as economic activity insufficiently covered by formal arrangements [1]. In Zimbabwe, successive FinScope MSME assessments report that informal enterprises dominate employment and contribute substantially to output while remaining largely outside the banking and taxation systems [2]. The literature consistently links this informality to constrained access to credit: without verifiable, structured financial records, enterprises cannot satisfy lender due-diligence, perpetuating a capital constraint that suppresses growth [9].

Digitalisation is repeatedly identified as a lever for SME productivity and formalisation. Studies of technology adoption in African SMEs report gains in record-keeping accuracy, inventory control and customer insight, moderated by barriers of cost, digital skills, infrastructure and trust [10], [11]. The Technology Acceptance Model (TAM) [12] and the Unified Theory of Acceptance and Use of Technology (UTAUT) [13] provide the dominant theoretical lenses: perceived usefulness, perceived ease of use, facilitating conditions and social influence predict adoption. These frameworks directly motivate SIMS AI's emphasis on low-friction UX, offline reliability and demonstrable, immediate value.

**Mobile money** is the standout success of African fintech. The literature documents how platforms such as M-Pesa in Kenya, and EcoCash in Zimbabwe, achieved deep penetration by meeting users where card infrastructure was absent [4], [14]. The GSMA's longitudinal reporting shows mobile money as the primary digital-value rail across the region [14]. This body of work justifies designing SIMS AI's payment layer around EcoCash, OneMoney, ZIPIT and PayNow rather than card settlement.

**Research gap (2.2):** the literature establishes both the need and the acceptance preconditions for SME digitalisation, but existing empirical studies evaluate generic or imported tools. There is little work on systems *architected from first principles* for the compound Zimbabwean constraint set — offline operation, multi-currency volatility and mobile-money settlement — which this study addresses.

## 2.3 Enterprise Architecture and ERP Systems

ERP integrates an organisation's core processes — sales, inventory, finance, HR — onto a shared data model [3]. The engineering literature offers durable architectural guidance. Fowler's *Patterns of Enterprise Application Architecture* codifies layering (presentation, domain, data-source) and patterns such as the Repository, Unit of Work and Data Mapper [15]. Evans' *Domain-Driven Design* argues for modelling around bounded contexts and a ubiquitous language, aligning software structure with business structure [16] — directly informing SIMS AI's modular decomposition (Inventory, Sales, Finance, HR, Identity contexts). Alistair Cockburn's Hexagonal (Ports-and-Adapters) architecture isolates domain logic from delivery and infrastructure concerns, enabling the same core to serve web, mobile and API adapters and to swap payment or notification providers behind ports [17].

For deployment and operational discipline, the **twelve-factor app** methodology [18] provides widely-adopted guidance (explicit dependencies, config in the environment, stateless processes, disposability) that maps naturally onto containerised deployment. The microservices literature [19] discusses decomposition trade-offs; for a system of SIMS AI's scale, a **modular monolith** with clear internal boundaries is the pragmatic choice, retaining the option to extract services (e.g., the ML inference service) as load demands — a position supported by contemporary architecture practice [19].

**Multi-tenancy** models — shared-database/shared-schema with a tenant discriminator, shared-database/separate-schema, and database-per-tenant — trade isolation against operational cost [20]. For many small tenants, shared-schema with a mandatory `tenant_id` predicate (enforced via PostgreSQL row-level security) offers the best cost/isolation balance, the approach SIMS AI adopts.

**Research gap (2.3):** established ERP architecture patterns assume reliable connectivity and centralised data. Their adaptation to an offline-first, client-authoritative model is under-explored, motivating Section 2.4.

## 2.4 Offline-First and Local-First Architectures

Kleppmann et al. articulate the **local-first** principle: software in which the primary copy of data lives on the user's device, the network is an enhancement rather than a prerequisite, and collaboration is achieved through synchronisation [5]. This directly answers Zimbabwe's connectivity constraint. The central technical challenge is **reconciliation** of concurrent, divergent edits.

Two families of solutions dominate the literature:

1. **Conflict-free Replicated Data Types (CRDTs)** [21], which guarantee that concurrent replicas converge to the same state without coordination, given commutative, associative, idempotent merge operations. CRDTs are powerful for collaborative editing but impose modelling constraints and metadata overhead.
2. **Operation logs with last-writer-wins (LWW) or domain-specific merge**, in which each device records an ordered log of mutations, tagged with logical clocks (e.g., Lamport timestamps [22] or hybrid logical clocks), replayed and merged on synchronisation.

For a transactional business system, most entities are *append-mostly* (a sale, once made, is immutable) or have a natural authority (stock quantity is a running total derived from immutable stock movements). SIMS AI therefore adopts an **event-sourced stock-movement ledger** — reconciliation reduces to merging two ordered sets of immutable movements — combined with LWW for editable master data (product name, price). This side-steps most CRDT complexity while preserving correctness, an approach consistent with event-sourcing guidance [23]. Idempotency (client-generated UUID transaction IDs, deduplicated server-side) prevents double-application on retry — a well-established reliability pattern [24].

**Research gap (2.4):** the local-first literature is strong on collaborative documents but thin on *financial-transactional* offline systems where correctness (no lost or double-counted sales) is paramount and currency values must be preserved. SIMS AI contributes a concrete design for this case.

## 2.5 Machine Learning for Demand Forecasting and Anomaly Detection

**Demand forecasting.** Classical time-series methods — ARIMA and exponential smoothing (Holt-Winters) — remain strong baselines, especially on short series [25]. Facebook's **Prophet** decomposes a series into trend, seasonality and holiday components and is robust to missing data and outliers, making it well-suited to noisy, gappy informal-sector sales [6]. Gradient-boosted decision trees (XGBoost, LightGBM) framed as regression over engineered calendar/lag features are frequently competitive and handle exogenous drivers (promotions, paydays) naturally [26]. The forecasting literature repeatedly cautions that on short, sparse series, deep-learning models (LSTM, Transformers) rarely outperform well-tuned statistical baselines and are harder to justify operationally [27] — a finding that directly shapes SIMS AI's model selection and its hypothesis H2. Evaluation uses MAPE, RMSE and MAE, with backtesting via rolling-origin cross-validation to avoid look-ahead bias [25].

**Reorder and inventory optimisation.** Classical inventory theory contributes the reorder-point and (s, S) policies and safety-stock formulations under demand uncertainty [28]. SIMS AI couples a demand forecast with lead-time and service-level parameters to compute reorder points, bridging the forecasting and operations literatures.

**Anomaly detection / fraud.** Unsupervised methods suit the informal setting, where labelled fraud examples are scarce. Isolation Forest [7] isolates anomalies through random partitioning and scales well; the Local Outlier Factor and one-class SVM are alternatives [29]. SIMS AI applies these to transaction streams (unusual discounts, void patterns, after-hours sales, cash-variance) to flag review candidates, framing fraud detection as anomaly detection rather than supervised classification.

**Recommendation.** Collaborative-filtering and association-rule mining (Apriori, FP-Growth) [30] support product-affinity ("customers who buy X also buy Y") and loyalty features; matrix-factorisation techniques generalise this [31].

## 2.6 Applied AI: Large Language Models and RAG

Large language models (LLMs) built on the Transformer architecture [32] exhibit strong natural-language understanding and generation. Their principal risk for a business-advice assistant is **hallucination** — fluent but ungrounded output. **Retrieval-Augmented Generation (RAG)** [8] mitigates this by retrieving relevant, authoritative context (here, the tenant's own sales, stock and finance figures) and conditioning generation on it, yielding answers that are both natural-language and factually grounded. SIMS AI's assistant uses RAG over per-tenant operational data, enabling queries such as *"Why did my profit fall last month?"* to be answered from real numbers with an auditable evidence trail. This design also enforces tenant isolation at the retrieval boundary — a security consideration examined in Chapter 4.

## 2.7 Security and Compliance Foundations

Security literature and practice converge on **defence in depth**. The OWASP Top Ten catalogues the prevalent web-application risks (injection, broken access control, cryptographic failures) that the design must counter [33]. Token-based stateless authentication via JSON Web Tokens is standardised in RFC 7519 [34], with the OWASP guidance recommending short-lived access tokens plus rotating refresh tokens. Multi-factor authentication (TOTP, RFC 6238 [35]) materially reduces account-takeover risk. Data-protection obligations arise under Zimbabwe's Cyber and Data Protection Act (Chapter 12:07) [36], motivating encryption in transit (TLS) and at rest, data-minimisation and auditability. Tax computation must conform to ZIMRA's VAT and presumptive-tax provisions [37].

## 2.8 Review of Comparable Systems

| System | Strengths | Limitations in the Zimbabwean informal context |
|---|---|---|
| SAP Business One / Oracle NetSuite | Comprehensive, mature, robust | Costly, complex, cloud/connectivity-dependent, no mobile-money or ZiG/USD dual-currency native support |
| QuickBooks / Xero | Strong SME accounting, good UX | Online-centric, card-payment oriented, weak offline POS, no local payment rails |
| Odoo (open source) | Modular, extensible, self-hostable | Heavy, assumes connectivity; offline POS limited; localisation for ZiG/EcoCash/ZIMRA not out-of-the-box |
| Local POS apps (e.g., Kazang, generic Android POS) | Affordable, mobile-money aware | Narrow (POS only), little analytics/AI, weak multi-shop, limited reporting |

The comparison exposes a clear niche: **no reviewed system simultaneously delivers offline-first reliability, native ZiG/USD transaction-time multi-currency, mobile-money-first payments, integrated AI analytics, and an affordable mobile-first footprint** for the Zimbabwean informal sector.

## 2.9 Conceptual Framework

SIMS AI is framed as the intersection of three literatures — **SME digitalisation** (the *why* and the adoption preconditions from TAM/UTAUT), **offline-first enterprise architecture** (the *how* of reliable operation under constraint), and **applied AI** (the *value multiplier* of forecasting, anomaly detection and grounded assistance). Adoption (dependent construct) is hypothesised to be driven by perceived usefulness (delivered by AI insight and financial visibility) and perceived ease of use (delivered by offline reliability and low-friction UX), moderated by facilitating conditions (device availability, intermittent connectivity) — the constructs the evaluation in Chapter 6 operationalises.

## 2.10 Research Gap and Chapter Summary

Synthesising the review: the need for and acceptance preconditions of SME digitalisation are established, enterprise-architecture patterns are mature, offline-first techniques exist (chiefly for collaborative documents), and lightweight ML and RAG are accessible. **What is absent is an integrated system, and a documented reference architecture, that unites these strands for the specific compound constraints of the Zimbabwean informal sector — offline operation, multi-currency volatility, mobile-money settlement and low digital skills.** SIMS AI addresses precisely this gap. The next chapter sets out the methodology by which the system is analysed, designed, built and evaluated.
