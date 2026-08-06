# Contributing to SIMS AI

Thanks for your interest! The short version:

## Workflow

1. Fork/branch from `main`; one focused change per branch.
2. Make sure the full check suite passes locally:
   ```bash
   cd backend && .venv/bin/python -m pytest -q   # backend tests
   python3 ml/train_forecast.py                  # ML harness runs
   cd web && npm run build                       # dashboard type-checks & builds
   ```
3. Open a pull request describing *what* and *why*. CI must be green.

## Design ground rules

- **Money is `Decimal`, end to end.** Never floats; every monetary event
  carries its currency and transaction-time exchange rate.
- **Ledgers are append-only.** Sales, payments, stock movements and journal
  facts are immutable; corrections are compensating events.
- **Every mutation is tenant-scoped and audit-logged.** New endpoints take
  the tenant from the auth context, filter by it, and call `audit.record`.
- **New sync entities** must be either immutable events (union-merge) or
  Lamport-versioned master data (LWW) — see `docs/research/chapter-4`.
- **Providers are ports.** Payment, SMS, email, LLM integrations go behind
  interfaces in `backend/app/adapters/`, never called inline from domain code.

## Code style

Backend: ruff, ~100-col lines, type hints. Web: TypeScript strict, Tailwind
utility classes. Match the style of surrounding code.
