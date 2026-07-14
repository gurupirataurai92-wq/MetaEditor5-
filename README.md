# MetaEditor5-

Creating a meta editor code for a risk taking bot that is able to executes trades even from low account balance

## IAX v6.0 "GODMODE" — Institutional Adaptive XAUUSD EA

- EA: [`MQL5/Experts/IAX_v6/IAX_v6_GODMODE.mq5`](MQL5/Experts/IAX_v6/IAX_v6_GODMODE.mq5)
- Docs: [`docs/IAX_v6_TECHNICAL.md`](docs/IAX_v6_TECHNICAL.md) — every formula, all design assumptions, parameter tuning guide, staged testing procedure.

Built from `MASTER_PROMPT_v6_GODMODE.md`: a 9-factor weighted decision engine, three-mode entry engine with laddered burst entries, regime-aware geometry, R-multiple + basket-group trade management, a separate swing module, a layered governor stack, online adaptive factor-weight learning, and full ops/verification logging (nothing fails silently). No profit is promised — read the technical doc's economic-honesty section before trading anything but a demo account.

This build has not yet been compiled in MetaEditor or backtested — do that first (Stage 1 lifecycle self-test in the Strategy Tester) before anything else.
