# SIMS AI — Research Dissertation

Distinction-oriented, university-level research write-up for **SIMS AI — Smart Informal Business Management Ecosystem**, an AI-driven, offline-first enterprise platform for modernising informal and small-to-medium enterprises in Zimbabwe.

All diagrams are authored as **Mermaid** and render directly on GitHub. IEEE citation numbers are consistent across chapters and resolve in `references.md`.

## Read in order

| # | Chapter | File |
|---|---|---|
| — | Front matter, declaration, abstract, ToC, abbreviations | [`00-front-matter.md`](00-front-matter.md) |
| 1 | Introduction (background, problem, objectives, questions, hypotheses, scope) | [`chapter-1-introduction.md`](chapter-1-introduction.md) |
| 2 | Literature Review (informal economy, ERP, offline-first, ML, RAG, gap) | [`chapter-2-literature-review.md`](chapter-2-literature-review.md) |
| 3 | Research Methodology & System Analysis (DSR, Agile, requirements, use-case/DFD) | [`chapter-3-methodology-analysis.md`](chapter-3-methodology-analysis.md) |
| 4 | System Design & Architecture (stack, DDD, ER, multi-currency, sync, ML, security, deployment) | [`chapter-4-system-design.md`](chapter-4-system-design.md) |
| 5 | Implementation (repo, code, sync engine, ML, CI) | [`chapter-5-implementation.md`](chapter-5-implementation.md) |
| 6 | Testing, Results & Evaluation (functional, NFR, security, usability, ML metrics) | [`chapter-6-testing-evaluation.md`](chapter-6-testing-evaluation.md) |
| 7 | Conclusions & Recommendations (findings, contributions, future work) | [`chapter-7-conclusion.md`](chapter-7-conclusion.md) |
| — | References (IEEE) | [`references.md`](references.md) |

## How to use these drafts

- Replace bracketed placeholders (`[Student Name]`, `[University Name]`, *report measured*) with your own details and measured results.
- The tables in Chapter 6 define the **instruments, targets and reporting format** — populate them from your own test runs to make the evaluation empirical.
- Diagrams can be exported to PNG/SVG (e.g., via the Mermaid Live Editor or `mmdc`) for inclusion in a Word/LaTeX submission.

## Research contributions (at a glance)

1. A **reference architecture** for offline-first, multi-tenant ERP in low-connectivity, high-volatility economies.
2. A **transaction-time multi-currency data model** that preserves the economic meaning of records under devaluation.
3. An **idempotent, event-sourced synchronisation design** for correctness-critical financial data.
4. An **empirical account** of lightweight forecasting and RAG-based business assistance on informal-sector data.
