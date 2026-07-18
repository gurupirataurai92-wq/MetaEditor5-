# SIMS AI — ML Module

Training and evaluation pipelines for the forecasting subsystem
(dissertation §5.8, §6.5).

Two tiers:

1. **Baseline (zero dependencies, runs anywhere):** `train_forecast.py`
   implements seasonal-naïve, moving-average and trend+weekday models with
   **rolling-origin backtesting** (MAPE/RMSE/MAE). The trend+weekday model is
   the same one the API serves — this pipeline is how its accuracy is
   reported in Chapter 6.
2. **Advanced (optional deps):** with `prophet` / `xgboost` installed, the
   same harness backtests those models for comparison; export to ONNX for
   serving is the documented path (`requirements-advanced.txt`).

## Run the baseline evaluation

```bash
python3 train_forecast.py            # synthetic demo series
python3 train_forecast.py sales.csv  # your own daily series: date,value
```

Outputs a per-model metric table — populate the Chapter 6 tables from it.
