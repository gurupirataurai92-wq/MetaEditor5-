#!/usr/bin/env python3
"""Rolling-origin backtest of demand-forecast models (dissertation §6.5.1).

Zero-dependency baseline harness: evaluates seasonal-naïve, moving-average
and trend+weekday models on a daily series with proper rolling-origin
cross-validation (no look-ahead), reporting MAPE / RMSE / MAE per model.

Usage:
    python3 train_forecast.py             # built-in synthetic demo series
    python3 train_forecast.py sales.csv   # CSV with header: date,value
"""
import csv
import math
import random
import statistics
import sys
from datetime import date, timedelta


# ----------------------------------------------------------------- models
def seasonal_naive(history: list[float], horizon: int) -> list[float]:
    """Repeat the value from one week ago (the standard hard-to-beat baseline)."""
    return [history[-7 + (i % 7)] if len(history) >= 7 else history[-1]
            for i in range(horizon)]


def moving_average(history: list[float], horizon: int, window: int = 7) -> list[float]:
    avg = statistics.mean(history[-window:]) if history else 0.0
    return [avg] * horizon


def trend_weekday(history: list[float], horizon: int) -> list[float]:
    """The model served by the SIMS AI API: least-squares trend ×
    multiplicative weekday factors."""
    n = len(history)
    xs = range(n)
    mean_x = (n - 1) / 2
    mean_y = statistics.mean(history)
    denom = sum((x - mean_x) ** 2 for x in xs) or 1.0
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, history)) / denom
    intercept = mean_y - slope * mean_x

    weekday_values: dict[int, list[float]] = {i: [] for i in range(7)}
    for i, value in enumerate(history):
        weekday_values[i % 7].append(value)
    factors = {
        wd: (statistics.mean(vs) / mean_y if vs and mean_y > 0 else 1.0)
        for wd, vs in weekday_values.items()
    }
    return [max(0.0, (intercept + slope * (n + i)) * factors[(n + i) % 7])
            for i in range(horizon)]


MODELS = {
    "seasonal-naive": seasonal_naive,
    "moving-average(7)": moving_average,
    "trend+weekday": trend_weekday,
}


# ---------------------------------------------------------------- metrics
def evaluate(actual: list[float], predicted: list[float]) -> dict[str, float]:
    errors = [a - p for a, p in zip(actual, predicted)]
    nonzero = [(a, p) for a, p in zip(actual, predicted) if a != 0]
    return {
        "MAE": statistics.mean(abs(e) for e in errors),
        "RMSE": math.sqrt(statistics.mean(e * e for e in errors)),
        "MAPE%": (statistics.mean(abs(a - p) / a for a, p in nonzero) * 100
                  if nonzero else float("nan")),
    }


def rolling_origin_backtest(series: list[float], *, horizon: int = 7,
                            min_train: int = 28, step: int = 7) -> dict[str, dict]:
    """Walk the origin forward; at each origin, train on everything before it
    and score the next `horizon` days. No fold ever sees its own future."""
    per_model: dict[str, dict[str, list[float]]] = {
        name: {"actual": [], "predicted": []} for name in MODELS
    }
    origin = min_train
    while origin + horizon <= len(series):
        train, test = series[:origin], series[origin:origin + horizon]
        for name, model in MODELS.items():
            per_model[name]["actual"].extend(test)
            per_model[name]["predicted"].extend(model(train, horizon))
        origin += step
    return {name: evaluate(d["actual"], d["predicted"])
            for name, d in per_model.items()}


# ------------------------------------------------------------------- data
def synthetic_series(days: int = 120, seed: int = 42) -> list[float]:
    """Informal-retail-like daily revenue: weekday seasonality, month-end
    payday bumps, mild trend, noise and occasional zero (closed) days."""
    rng = random.Random(seed)
    start = date(2026, 1, 1)
    weekday_factor = [1.0, 0.9, 0.95, 1.0, 1.25, 1.6, 0.5]  # Sat peak, Sun low
    series = []
    for i in range(days):
        day = start + timedelta(days=i)
        base = 80 + 0.3 * i                             # gentle growth
        payday = 1.5 if day.day >= 25 else 1.0          # month-end salaries
        value = base * weekday_factor[day.weekday()] * payday
        value *= rng.uniform(0.75, 1.25)                # demand noise
        if rng.random() < 0.03:
            value = 0.0                                 # closed / power cut
        series.append(round(value, 2))
    return series


def load_csv(path: str) -> list[float]:
    with open(path, newline="") as f:
        return [float(row["value"]) for row in csv.DictReader(f)]


def main() -> None:
    series = load_csv(sys.argv[1]) if len(sys.argv) > 1 else synthetic_series()
    print(f"Series length: {len(series)} days — rolling-origin backtest "
          "(horizon 7, step 7)\n")
    results = rolling_origin_backtest(series)
    width = max(len(name) for name in results)
    print(f"{'model'.ljust(width)}  {'MAPE%':>8}  {'RMSE':>8}  {'MAE':>8}")
    for name, metrics in sorted(results.items(), key=lambda kv: kv[1]["MAPE%"]):
        print(f"{name.ljust(width)}  {metrics['MAPE%']:8.1f}  "
              f"{metrics['RMSE']:8.2f}  {metrics['MAE']:8.2f}")
    best = min(results.items(), key=lambda kv: kv[1]["MAPE%"])
    print(f"\nBest by MAPE: {best[0]} ({best[1]['MAPE%']:.1f}%)")


if __name__ == "__main__":
    main()
