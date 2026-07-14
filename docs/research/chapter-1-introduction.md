# Chapter 1 — Introduction

## 1.1 Introduction and Background to the Study

Micro, small and medium enterprises (MSMEs) are the backbone of the Zimbabwean economy. The FinScope MSME survey and subsequent national assessments estimate that the informal sector engages the majority of the country's economically active population and contributes a significant proportion of gross domestic product [1], [2]. These enterprises — spaza shops, hardware retailers, wholesalers, tuck-shops, salons, fabricators and market traders — operate in an environment characterised by scarce capital, thin margins, and near-total absence of formal management infrastructure.

Globally, the digitalisation of small business through Enterprise Resource Planning (ERP) systems has produced substantial, well-documented gains in efficiency, transparency and decision quality [3]. Commercial platforms such as SAP Business One, Oracle NetSuite, Microsoft Dynamics 365, Odoo and QuickBooks have matured into comprehensive ecosystems. However, these systems were architected for enterprises operating in high-connectivity, stable-currency, card-settlement economies. When transplanted into the Zimbabwean informal context they fail against three structural realities:

1. **Connectivity and power intermittency.** Reliable, always-on internet and grid electricity cannot be assumed. A cloud-only ERP that stalls when the network drops is unusable at the point of sale.
2. **Currency volatility and multi-currency operation.** Following the 2024 introduction of the Zimbabwe Gold (ZiG) circulating alongside the United States Dollar (USD), businesses transact daily across two or more currencies at exchange rates that shift materially over short horizons. Storing only a currency label — the assumption baked into most ERPs — irretrievably loses the economic meaning of historical transactions.
3. **Mobile-money-first payments.** Value is moved principally through EcoCash, OneMoney, ZIPIT and PayNow rather than through the card rails that Western point-of-sale systems assume [4].

The convergence of two technological shifts makes a locally-engineered solution newly feasible. First, offline-first application architectures — local-first data stores with deferred, conflict-aware synchronisation — have matured into a deployable engineering discipline [5]. Second, machine learning and, more recently, large language models have become accessible through commodity libraries and APIs, allowing forecasting, anomaly detection and natural-language business assistance to be embedded in modest applications [6], [7], [8]. **SIMS AI — the Smart Informal Business Management Ecosystem** — is conceived at this convergence: an offline-first, AI-augmented, multi-currency business-management platform designed from first principles for the Zimbabwean informal and SME sector.

## 1.2 Statement of the Problem

Despite the demonstrated value of business digitalisation, informal and small enterprises in Zimbabwe remain largely undigitised. The core problem is the **absence of an accessible, context-appropriate business-management system**, which manifests as:

- **Opaque financial position.** Owners cannot reliably answer whether the business is profitable, which products drive margin, or whether cash-flow will cover next month's obligations, because records are paper-based, fragmented or absent.
- **Reactive, intuition-driven inventory decisions**, producing simultaneous stock-outs of fast-movers and dead capital tied up in slow-movers, with no systematic reorder discipline.
- **Undetected leakage and fraud.** Without transaction audit trails and anomaly monitoring, theft, pricing errors and cash shrinkage go unnoticed.
- **Exclusion from formal credit**, because the enterprise cannot produce the verifiable financial history that lenders require.
- **Unsuitability of existing tools.** The commercial ERPs that could address these needs assume constant connectivity, single/stable currency and card payments, and are priced and complexity-scoped for formal enterprises.

The problem this research addresses is therefore: *How can an enterprise-grade business-management system be designed and implemented so as to be genuinely usable, valuable and adoptable by Zimbabwean informal and small businesses, given the sector's connectivity, currency, payment and skills constraints?*

## 1.3 Research Aim

To design, implement and evaluate **SIMS AI**, a modular, secure, offline-first and AI-augmented enterprise business-management ecosystem that modernises the operations of Zimbabwean informal and small-to-medium enterprises through automation, analytics and integrated digital finance.

## 1.4 Research Objectives

**RO1.** To investigate the operational, financial and technological constraints faced by Zimbabwean informal/SME businesses, and to elicit and specify the corresponding functional and non-functional requirements.

**RO2.** To design an enterprise reference architecture — layered, modular, multi-tenant and offline-first — that satisfies these requirements while adhering to established software-engineering principles (DDD, twelve-factor, defence-in-depth).

**RO3.** To implement the core system: a REST API backend, relational data tier, web administration dashboard, Android and Progressive Web applications, and the supporting ML/AI subsystem.

**RO4.** To design a transaction-time multi-currency data model and an offline-first synchronisation mechanism resilient to intermittent connectivity and exchange-rate volatility.

**RO5.** To develop and evaluate the AI/ML subsystem — sales forecasting, reorder and inventory prediction, cash-flow projection, anomaly-based fraud detection, and a retrieval-augmented conversational business assistant.

**RO6.** To evaluate the resulting system against its functional, non-functional (performance, security, usability) and contextual objectives, and to derive conclusions and recommendations.

## 1.5 Research Questions

- **RQ1.** What are the principal barriers to business digitalisation in the Zimbabwean informal/SME sector, and what requirements do they impose on a management system?
- **RQ2.** What software architecture best reconciles enterprise-grade modularity and security with offline-first operation under intermittent connectivity?
- **RQ3.** How can multi-currency transactions be modelled so that historical financial records remain economically meaningful under exchange-rate volatility?
- **RQ4.** Which machine-learning approaches produce useful demand forecasts and anomaly detection given the short, noisy, sparse transaction histories typical of informal businesses?
- **RQ5.** To what extent does the implemented system meet its functional, performance, security and usability objectives?

## 1.6 Research Hypothesis

**H1.** An offline-first architecture with deferred synchronisation can deliver point-of-sale and inventory operations with no perceptible degradation in the availability or latency of core transactions during network outages, relative to online operation.

**H0 (null).** Offline operation materially degrades the availability or correctness of core transactions.

**H2.** Lightweight time-series and statistical-learning models (e.g., exponential smoothing, Prophet, gradient-boosted trees) produce demand forecasts of practically useful accuracy (target MAPE ≤ 20% for fast-moving items) on informal-sector sales histories, without requiring deep-learning-scale data.

## 1.7 Significance of the Study

- **To business owners:** a practical instrument for financial visibility, inventory discipline, fraud reduction and, ultimately, creditworthiness.
- **To the national economy:** a pathway to formalisation, improved tax compliance (ZIMRA VAT and presumptive-tax computation) and financial inclusion.
- **To the software-engineering body of knowledge:** a documented reference architecture for offline-first, multi-currency ERP in low-connectivity, high-volatility economies — a context under-represented in the literature.
- **To academia:** an empirical study of lightweight forecasting on informal-sector data and of retrieval-augmented conversational assistance grounded in operational business data.

## 1.8 Scope and Delimitations

The study designs the **full ecosystem** (Android app, PWA, admin dashboard, REST API, relational database, AI/ML module) and implements a demonstrable, commercially-credible **vertical core**: authentication with RBAC, multi-shop tenancy, inventory, point-of-sale with barcode support, customer/supplier management, invoicing and receipts, financial reporting, one end-to-end forecasting model, anomaly-based fraud detection, and the AI assistant. Remaining catalogue features (full payroll runs, loyalty, complete IFRS-format statements, deep integrations) are architected and documented as extension points and, where feasible, stubbed.

**Delimitations:** Live production integrations with EcoCash, ZIPIT, PayNow and banking rails are implemented against sandbox/mock gateways behind a uniform payment-provider interface; production certification with each provider is out of scope. Fiscalisation device certification with ZIMRA is designed for but not certified. The evaluation is conducted with a purposive sample of businesses and synthetic/representative datasets rather than a national field trial.

## 1.9 Assumptions

- Participating businesses possess at least one Android smartphone.
- Intermittent — not permanently absent — connectivity is available for periodic synchronisation.
- Users have basic smartphone literacy but not accounting or IT expertise; the interface must accommodate this.

## 1.10 Limitations

- Access to large, longitudinal, real transaction datasets is constrained; some evaluation uses representative synthetic data calibrated to observed patterns.
- Currency and regulatory conditions in Zimbabwe evolve rapidly; specific rates and rules are parameterised rather than hard-coded.
- The evaluation horizon is bounded by the academic timeline, limiting long-run adoption measurement.

## 1.11 Definition of Key Terms

- **Informal enterprise:** a business operating outside full formal registration, taxation and regulatory frameworks.
- **Offline-first:** an architecture in which the local device is the primary data store and remains fully functional without network connectivity, synchronising opportunistically.
- **Multi-tenancy:** a single system instance serving multiple isolated businesses (tenants).
- **Transaction-time currency capture:** persisting the currency, amount and applicable exchange rate as at the moment a transaction occurred.
- **Retrieval-Augmented Generation (RAG):** grounding a language model's responses in retrieved, authoritative source data rather than parametric memory [8].

## 1.12 Dissertation Structure

Chapter 2 reviews the literature on SME digitalisation, ERP architecture, offline-first synchronisation, forecasting and applied AI. Chapter 3 presents the research methodology and system analysis. Chapter 4 details the system design and architecture with full UML, ER, DFD and deployment diagrams. Chapter 5 describes the implementation. Chapter 6 reports testing, results and evaluation. Chapter 7 concludes and recommends further work.

## 1.13 Chapter Summary

This chapter established the socio-economic and technological context for SIMS AI, articulated the problem of the digitalisation gap in Zimbabwe's informal sector, and framed it against the specific constraints of connectivity, currency volatility and mobile-money payments. It stated the aim, objectives, research questions, hypotheses and scope that direct the remainder of the dissertation.
