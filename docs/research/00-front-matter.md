# SIMS AI — Smart Informal Business Management Ecosystem

### An AI-Driven, Offline-First Enterprise Platform for the Modernisation of Informal and Small-to-Medium Enterprises in Zimbabwe

**A Dissertation Submitted in Partial Fulfilment of the Requirements for the Degree of Bachelor of Science Honours in Software / Information Systems Engineering**

---

| | |
|---|---|
| **Author** | *[Student Name]* |
| **Registration No.** | *[Reg No.]* |
| **Supervisor** | *[Supervisor Name]* |
| **Department** | Department of Computer Science / Information Systems |
| **Institution** | *[University Name]*, Zimbabwe |
| **Academic Year** | 2025 / 2026 |
| **Version** | 1.0 (Draft) |

---

## Declaration

I, the undersigned, declare that this dissertation titled *"SIMS AI — Smart Informal Business Management Ecosystem"* and the work presented in it are my own. I confirm that:

- This work was done wholly while in candidature for a research degree at this University.
- Where I have consulted the published work of others, this is always clearly attributed using IEEE citation style.
- Where I have quoted from the work of others, the source is always given.
- I have acknowledged all main sources of help.

**Signed:** ___________________  **Date:** ___________________

## Approval

This dissertation has been submitted for examination with my approval as the University supervisor.

**Supervisor:** ___________________  **Date:** ___________________

---

## Abstract

The informal sector accounts for an estimated 60–76% of Zimbabwe's economically active population and a substantial share of national economic activity, yet the overwhelming majority of informal and small-to-medium enterprises (SMEs) operate without any digital business-management infrastructure. Record-keeping is predominantly paper-based or absent, inventory decisions are made on intuition, cash-flow is opaque, and access to formal credit is impaired by the lack of verifiable financial history. Compounding these structural challenges are three environment-specific constraints that render most commercial Enterprise Resource Planning (ERP) systems unsuitable: (i) intermittent electricity and mobile-data connectivity, (ii) a volatile multi-currency regime (the Zimbabwe Gold, ZiG, circulating alongside the United States Dollar) requiring transaction-time exchange-rate capture, and (iii) a mobile-money-dominated payments landscape (EcoCash, OneMoney, ZIPIT, PayNow) rather than card-based settlement.

This dissertation presents the design, implementation and evaluation of **SIMS AI**, a modular, offline-first, AI-augmented business-management ecosystem engineered specifically for the Zimbabwean informal and SME context. The system comprises a REST API backend, a responsive web administration dashboard, an Android application, a Progressive Web Application (PWA), a relational data tier, and an integrated Machine Learning (ML) and Artificial Intelligence (AI) subsystem. Core capabilities include point-of-sale, inventory management, customer and supplier management, payroll, invoicing and financial reporting, delivered atop a multi-tenant, role-based-access-controlled, offline-first synchronisation architecture. The AI subsystem provides demand forecasting, automatic reorder prediction, cash-flow projection, anomaly-based fraud detection, and a retrieval-augmented conversational business assistant grounded in each enterprise's own operational data.

The system was designed following established enterprise software-engineering principles — layered/hexagonal architecture, domain-driven design, and the twelve-factor methodology — and evaluated against functional, non-functional, and usability criteria using a mixed-methods approach. Results demonstrate that a locally-contextualised, AI-driven ecosystem can materially reduce the record-keeping burden, surface actionable operational intelligence, and function reliably under Zimbabwe's connectivity and currency constraints. The dissertation contributes (1) a reference architecture for offline-first ERP in low-connectivity economies, (2) a transaction-time multi-currency data model robust to hyperinflationary volatility, and (3) an empirical evaluation of lightweight forecasting models for informal-sector sales data.

**Keywords:** Informal economy; SME digitalisation; ERP; offline-first architecture; conflict-free synchronisation; demand forecasting; anomaly detection; retrieval-augmented generation; mobile money; multi-currency; Zimbabwe.

---

## Acknowledgements

*[Reserved for acknowledgements — supervisor, department, family, participating businesses.]*

---

## Table of Contents

1. **Chapter 1 — Introduction** — `chapter-1-introduction.md`
2. **Chapter 2 — Literature Review** — `chapter-2-literature-review.md`
3. **Chapter 3 — Research Methodology & System Analysis** — `chapter-3-methodology-analysis.md`
4. **Chapter 4 — System Design & Architecture** — `chapter-4-system-design.md`
5. **Chapter 5 — Implementation** — `chapter-5-implementation.md`
6. **Chapter 6 — Testing, Results & Evaluation** — `chapter-6-testing-evaluation.md`
7. **Chapter 7 — Conclusions & Recommendations** — `chapter-7-conclusion.md`
8. **References (IEEE)** — `references.md`

### List of Abbreviations

| Abbr. | Meaning |
|---|---|
| AI | Artificial Intelligence |
| API | Application Programming Interface |
| CRDT | Conflict-free Replicated Data Type |
| DDD | Domain-Driven Design |
| DFD | Data Flow Diagram |
| ERD | Entity-Relationship Diagram |
| ERP | Enterprise Resource Planning |
| JWT | JSON Web Token |
| KYC | Know Your Customer |
| MAPE | Mean Absolute Percentage Error |
| ML | Machine Learning |
| PWA | Progressive Web Application |
| RAG | Retrieval-Augmented Generation |
| RBAC | Role-Based Access Control |
| RMSE | Root Mean Square Error |
| SME | Small-to-Medium Enterprise |
| VAT | Value-Added Tax |
| ZiG | Zimbabwe Gold (currency) |
| ZIMRA | Zimbabwe Revenue Authority |
