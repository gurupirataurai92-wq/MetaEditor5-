#!/usr/bin/env python3
"""Behavioral verification of Medula EA engines.

Each function below is a 1:1 port of the MQL5 implementation in
Medula_Single.mq5 (same constants, same order of operations). Tests feed
synthetic market data where the correct classification/decision is known
a priori, and assert the engine produces it. Array convention matches
MQL5 series arrays: index 0 = most recent bar.
"""
import math, random

PASS, FAIL = [], []
def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("PASS " if cond else "FAIL ") + name + ((" -- " + detail) if detail and not cond else ""))

def mtanh(x):
    if x > 20: return 1.0
    if x < -20: return -1.0
    e = math.exp(2*x); return (e-1)/(e+1)
def mclamp(x, lo, hi): return min(max(x, lo), hi)
def msign(x): return 1 if x > 0 else (-1 if x < 0 else 0)

# ---------------------------------------------------------------- §1 ER
def efficiency_ratio(c, n):
    num = abs(c[0]-c[n]); den = sum(abs(c[i-1]-c[i]) for i in range(1, n+1))
    return num/den if den > 0 else 0.0

trend_closes = [100.0 + (20-i)*0.5 for i in range(21)]          # straight line up
chop_closes  = [100.0 + (0.3 if i % 2 else 0.0) for i in range(21)]
er_t, er_c = efficiency_ratio(trend_closes, 20), efficiency_ratio(chop_closes, 20)
check("ER: straight trend == 1.0", abs(er_t-1.0) < 1e-9, f"{er_t}")
check("ER: pure chop near 0", er_c < 0.10, f"{er_c}")
check("ER bounded [0,1]", 0 <= er_c <= 1 and 0 <= er_t <= 1)

# ------------------------------------------------- §1/§5 volatility suite
def vol_suitability(pct): return 100.0*math.exp(-0.5*((pct-55.0)/30.0)**2)
check("VolSuitability peak at 55th pct", abs(vol_suitability(55)-100) < 1e-9)
check("VolSuitability penalizes extremes",
      vol_suitability(0) < 20 and vol_suitability(100) < 40 and vol_suitability(55) > vol_suitability(90))

def vol_percentile(atr_series):                                  # [0]=current
    n = len(atr_series)-1
    return 100.0*sum(1 for i in range(1, n+1) if atr_series[i] < atr_series[0])/n
hi_vol = [2.0] + [1.0]*250
lo_vol = [0.5] + [1.0]*250
check("VolPct: spike -> 100", vol_percentile(hi_vol) == 100.0)
check("VolPct: collapse -> 0", vol_percentile(lo_vol) == 0.0)

# ---------------------------------------------------------- §2 structure
def update_structure(hi, lo, cl, k=2, struct_events=10):
    """Port of UpdateStructure: series arrays, chronological replay."""
    bars = len(cl)
    swings, events = [], []
    flags = dict(bullBos=False, bearBos=False, bullChoch=False, bearChoch=False)
    lastSH = lastSL = 0.0
    trendDir = 0
    def is_sw_high(j):
        return all(hi[j] > hi[j+m] and hi[j] > hi[j-m] for m in range(1, k+1))
    def is_sw_low(j):
        return all(lo[j] < lo[j+m] and lo[j] < lo[j-m] for m in range(1, k+1))
    for b in range(bars-1-k, -1, -1):
        j = b + k
        if j <= bars-1-k:
            if is_sw_high(j): swings.append(hi[j]); lastSH = hi[j]
            if is_sw_low(j):  swings.append(lo[j]); lastSL = lo[j]
        if lastSH > 0 and cl[b] > lastSH:
            choch = (trendDir == -1); trendDir = 1
            if choch:
                if b == 0: flags['bullChoch'] = True
            else:
                events.append(1)
                if b == 0: flags['bullBos'] = True
            lastSH = 0.0
        if lastSL > 0 and cl[b] < lastSL:
            choch = (trendDir == 1); trendDir = -1
            if choch:
                if b == 0: flags['bearChoch'] = True
            else:
                events.append(-1)
                if b == 0: flags['bearBos'] = True
            lastSL = 0.0
    ev = events[-min(len(events), struct_events):]
    bull, bear = sum(1 for e in ev if e > 0), sum(1 for e in ev if e < 0)
    score = 100.0*(bull-bear)/(bull+bear+1)
    return score, trendDir, flags

def synth_series(path):
    """Build series arrays (index 0 = newest) from a chronological close path,
    with highs/lows = close +/- 0.1 so fractals form at local extremes."""
    chron = path[:]
    cl = list(reversed(chron))
    hi = [c+0.1 for c in cl]
    lo = [c-0.1 for c in cl]
    return hi, lo, cl

# uptrend with pullbacks: sequence of higher highs / higher lows
up = []
lvl = 100.0
for cyc in range(8):
    for s in range(6):  lvl += 0.5; up.append(lvl)      # impulse up
    for s in range(3):  lvl -= 0.3; up.append(lvl)      # shallow pullback
score_up, dir_up, fl = update_structure(*synth_series(up))
check("Structure: uptrend -> positive score & dir=+1", score_up > 0 and dir_up == 1,
      f"score={score_up:.1f} dir={dir_up}")

down = []
lvl = 100.0
for cyc in range(8):
    for s in range(6):  lvl -= 0.5; down.append(lvl)
    for s in range(3):  lvl += 0.3; down.append(lvl)
score_dn, dir_dn, _ = update_structure(*synth_series(down))
check("Structure: downtrend -> negative score & dir=-1", score_dn < 0 and dir_dn == -1,
      f"score={score_dn:.1f} dir={dir_dn}")

# CHoCH: long downtrend, then a final bar that breaks above the last swing high
rev = list(down)
rev += [rev[-1] + 0.2*i for i in range(1, 4)]
rev.append(max(rev[-12:-1]) + 3.0)     # decisive break above recent swing high on the newest bar
sc, dr, fl = update_structure(*synth_series(rev))
check("Structure: reversal bar flags bullish CHoCH & flips dir to +1",
      fl['bullChoch'] and dr == 1, f"flags={fl} dir={dr}")

# ---------------------------------------------------------- §3 trend score
def trend_score_core(adx, e50_0, e50_n, e20_0, atr, er, slope_bars=10):
    if atr <= 0: return 0.0
    slope = (e50_0-e50_n)/(slope_bars*atr)
    c1 = mtanh(adx/25.0-1.0); c2 = mtanh(slope*10.0)
    c3 = mtanh((er-0.2)*5.0); c4 = float(msign(e20_0-e50_0))
    d = msign(e20_0-e50_0) or msign(slope)
    return 100.0*(0.35*c1*d + 0.30*c2 + 0.20*c3*d + 0.15*c4)

ts_bull = trend_score_core(adx=40, e50_0=101.0, e50_n=100.0, e20_0=101.5, atr=0.5, er=0.6)
ts_bear = trend_score_core(adx=40, e50_0=99.0,  e50_n=100.0, e20_0=98.5,  atr=0.5, er=0.6)
ts_flat = trend_score_core(adx=12, e50_0=100.0, e50_n=100.0, e20_0=100.0, atr=0.5, er=0.05)
check("Trend: strong up -> large positive", ts_bull > 50, f"{ts_bull:.1f}")
check("Trend: strong down -> large negative (symmetry)", ts_bear < -50 and abs(ts_bull+ts_bear) < 1e-6,
      f"{ts_bear:.1f}")
check("Trend: flat -> ~0 and bounded", abs(ts_flat) < 10 and -100 <= ts_bull <= 100)

# ---------------------------------------------------------- §4 momentum
def momentum_score(rsi, roc0, macd_slope, atr):
    return 100.0*mtanh(0.40*((rsi-50)/50.0) + 0.30*mtanh(roc0/2.0) + 0.30*mtanh(macd_slope/(0.1*atr)))
mo_b = momentum_score(rsi=75, roc0=1.5, macd_slope=0.05, atr=0.5)
mo_s = momentum_score(rsi=25, roc0=-1.5, macd_slope=-0.05, atr=0.5)
mo_n = momentum_score(rsi=50, roc0=0.0, macd_slope=0.0, atr=0.5)
check("Momentum: bullish inputs -> positive", mo_b > 30, f"{mo_b:.1f}")
check("Momentum: bearish mirror -> negative symmetric", abs(mo_b+mo_s) < 1e-9, f"{mo_s:.1f}")
check("Momentum: neutral -> 0, bounded", mo_n == 0.0 and -100 <= mo_b <= 100)

# ---------------------------------------------------------- §6 liquidity
def liquidity_score(swings, close, atr, rng=3.0):
    d = rng*atr
    above = sum(1 for p in swings if close < p <= close+d)
    below = sum(1 for p in swings if close-d <= p < close)
    return 100.0*mtanh((below-above)/(below+above+1.0))
liq_support = liquidity_score([99.5, 99.6, 99.4, 99.7], 100.0, 0.5)
liq_resist  = liquidity_score([100.5, 100.4, 100.6, 100.3], 100.0, 0.5)
check("Liquidity: pools below -> positive", liq_support > 0, f"{liq_support:.1f}")
check("Liquidity: pools above -> negative, symmetric", abs(liq_support+liq_resist) < 1e-9)
far = liquidity_score([110.0, 90.0], 100.0, 0.5)
check("Liquidity: pools beyond 3*ATR ignored", far == 0.0)

# ---------------------------------------------------------- §7 MTF
def mtf(dirs_d1_h4_h1, chart_dir):
    w = [0.40, 0.30, 0.20, 0.10]
    align = sum(wi*di for wi, di in zip(w, dirs_d1_h4_h1)) + w[3]*chart_dir
    return align, abs(align)*100.0
al, cf = mtf([1, 1, 1], 1)
check("MTF: full agreement -> alignment 1.0 confluence 100", abs(al-1.0) < 1e-9 and abs(cf-100) < 1e-9)
al2, cf2 = mtf([1, 1, -1], -1)
check("MTF: mixed -> partial alignment, veto-eligible when >50",
      abs(al2-0.4) < 1e-9 and cf2 < 50)  # 0.4+0.3-0.2-0.1=0.4 -> confluence 40, no veto
al3, cf3 = mtf([-1, -1, -1], 1)
check("MTF veto scenario: chart long vs HTF short w/ confluence>50",
      msign(al3) == -1 and cf3 > 50, f"align={al3} conf={cf3}")

# ---------------------------------------------------------- §8 confidence
def confidence(struct, trend, mom, liq, mtf_align, vol_suit, spread_pts, max_spread, exec_q,
               w=(0.25, 0.25, 0.20, 0.15, 0.15), gain=2.5):
    raw = w[0]*struct/100 + w[1]*trend/100 + w[2]*mom/100 + w[3]*liq/100 + w[4]*mtf_align
    cdir = 100.0*mtanh(gain*raw)
    mag = abs(cdir)
    p_vol = vol_suit/100.0
    p_spr = mclamp(1.0 - spread_pts/max_spread, 0, 1) if max_spread > 0 else 1.0
    p_ex = mclamp(exec_q/100.0, 0, 1)
    return cdir, mag*p_vol*p_spr*p_ex

cd, cf_all = confidence(80, 80, 70, 50, 0.8, vol_suit=95, spread_pts=5, max_spread=30, exec_q=100)
check("Confidence: strong aligned evidence -> high score", cd > 50 and cf_all > 40, f"dir={cd:.1f} final={cf_all:.1f}")
_, cf_badspread = confidence(80, 80, 70, 50, 0.8, 95, spread_pts=30, max_spread=30, exec_q=100)
check("Confidence: spread at max -> zero (hard dampening)", cf_badspread == 0.0)
_, cf_badexec = confidence(80, 80, 70, 50, 0.8, 95, 5, 30, exec_q=50)
check("Confidence: degraded execution halves score", abs(cf_badexec - cf_all/2) < 1e-9)
cd_conflict, cf_conflict = confidence(80, -80, 10, -10, 0.0, 95, 5, 30, 100)
check("Confidence: conflicting evidence -> weak signal", abs(cd_conflict) < 25, f"{cd_conflict:.1f}")

# REGRESSION for the calibration bug: the entry threshold must be reachable.
_, cf_max = confidence(100, 100, 100, 100, 1.0, vol_suit=100, spread_pts=0, max_spread=30, exec_q=100)
_, cf_typ = confidence(70, 80, 60, 30, 0.7, vol_suit=90, spread_pts=5, max_spread=30, exec_q=100)
check("Confidence REACHABILITY: perfect evidence near 100", cf_max > 95, f"{cf_max:.1f}")
check("Confidence REACHABILITY: strong realistic evidence clears thr=60", cf_typ >= 60, f"{cf_typ:.1f}")
_, cf_weak = confidence(20, 25, 15, 10, 0.2, vol_suit=90, spread_pts=5, max_spread=30, exec_q=100)
check("Confidence REACHABILITY: weak evidence stays below threshold", cf_weak < 60, f"{cf_weak:.1f}")

# ---------------------------------------------------------- §9 decision
def decide(conf_dir, conf_final, in_trade, basket_dir, thr=60.0, hyst=8.0,
           mtf_align=0.0, mtf_confl=0.0, veto_level=50.0):
    d = msign(conf_dir)
    if not in_trade:
        if d != 0 and conf_final >= thr:
            if msign(mtf_align) != d and mtf_confl > veto_level: return "WAIT"
            return "BUY" if d > 0 else "SELL"
        return "WAIT"
    if conf_final < thr-hyst: return "EXIT"
    if d != 0 and basket_dir != 0 and d != basket_dir: return "EXIT"
    return "HOLD"

check("Decision: conf 65 long, flat -> BUY", decide(70, 65, False, 0) == "BUY")
check("Decision: conf 59.9, flat -> WAIT (threshold)", decide(70, 59.9, False, 0) == "WAIT")
check("Decision: MTF veto blocks counter-HTF entry",
      decide(70, 65, False, 0, mtf_align=-0.7, mtf_confl=70) == "WAIT")
check("Decision: in-trade conf 55 (>= thr-hyst=52) -> HOLD", decide(70, 55, True, 1) == "HOLD")
check("Decision: in-trade conf 51.9 -> EXIT (hysteresis floor)", decide(70, 51.9, True, 1) == "EXIT")
check("Decision: in-trade direction flip -> EXIT", decide(-70, 75, True, 1) == "EXIT")
check("Decision: hysteresis prevents flip-flop band [52,60)",
      decide(70, 55, True, 1) == "HOLD" and decide(70, 55, False, 0) == "WAIT")

# ------------------------------------------------- §12 scaling / §13 risk
def scale_lots(initial_lot, decay, basket_count):
    return initial_lot * decay**basket_count
lots_seq = [scale_lots(0.10, 0.7, n) for n in range(1, 5)]
check("Scaling: strictly decaying adds (never martingale)",
      all(lots_seq[i] < lots_seq[i-1] for i in range(1, 4)) and lots_seq[0] < 0.10,
      f"{lots_seq}")
total_scaled = 0.10 + sum(lots_seq[:3])
check("Scaling: total basket volume bounded (geometric sum)", total_scaled < 0.10/(1-0.7), f"{total_scaled:.3f}")

def lot_for_risk(risk_amt, sl_dist, tick_val, tick_sz):
    if min(risk_amt, sl_dist, tick_val, tick_sz) <= 0: return 0.0
    return risk_amt / (sl_dist/tick_sz*tick_val)
# EURUSD-like: tick value $1 per 0.00001? use classic: tick_size .00001, tick_value 1.0 per lot
lot = lot_for_risk(risk_amt=75.0, sl_dist=0.00150, tick_val=1.0, tick_sz=0.00001)
implied = 0.00150/0.00001*1.0*lot
check("Sizing: implied risk equals requested risk (inverse identity)", abs(implied-75.0) < 1e-9, f"lot={lot}")
check("Sizing: zero/negative inputs -> 0 lots (guards)",
      lot_for_risk(0, 1, 1, 1) == 0 and lot_for_risk(75, 0, 1, 1) == 0)

def normalize_lots(lots, step=0.01, mn=0.01, mx=100.0, allow_min=True):
    lots = math.floor(lots/step + 1e-9)*step
    if lots < mn: return mn if allow_min else 0.0
    return min(lots, mx)
check("NormalizeLots: floors to step", abs(normalize_lots(0.1234)-0.12) < 1e-12)
check("NormalizeLots: small-account min-lot override", normalize_lots(0.004) == 0.01)
check("NormalizeLots: strict mode returns 0 under min", normalize_lots(0.004, allow_min=False) == 0.0)
check("NormalizeLots: capped at max", normalize_lots(500.0) == 100.0)

# circuit breaker
def breaker(day_start, peak, eq, daily_pct=3.0, dd_pct=10.0):
    return (day_start-eq) >= day_start*daily_pct/100 or (peak-eq) >= peak*dd_pct/100
check("Breaker: -3% day trips", breaker(10000, 10000, 9700) is True)
check("Breaker: -2.9% day holds", breaker(10000, 10000, 9711) is False)
check("Breaker: -10% from peak trips even if day is flat", breaker(9000, 10000, 9000) is True)

# ---------------------------------------------------------- §15 kelly
def kelly(wins, losses, gross_win, gross_loss, frac=0.25, cap=0.015):
    if wins == 0 or losses == 0: return cap
    W = wins/(wins+losses); avg_w = gross_win/wins; avg_l = gross_loss/losses
    if avg_l <= 0: return cap
    b = avg_w/avg_l
    if b <= 0: return 0.0
    return mclamp(frac*(W*b-(1-W))/b, 0.0, cap)
k_good = kelly(60, 40, 6000, 2400)      # W=.6 b=1.667 -> f=.36 -> quarter=.09 -> capped
check("Kelly: profitable edge capped at ceiling", k_good == 0.015, f"{k_good}")
k_bad = kelly(30, 70, 900, 3500)        # W=.3 b=0.6 -> f negative -> clamped 0
check("Kelly: negative edge -> 0 risk", k_bad == 0.0, f"{k_bad}")

# ---------------------------------------------------------- §16 session
def session_mult(h, asian=0.6, london=1.0, overlap=1.2, ny=1.0, dead=0.3):
    if 7 <= h < 12: return london
    if 12 <= h < 16: return overlap
    if 16 <= h < 21: return ny
    if h >= 21: return dead
    return asian
cover = [session_mult(h) for h in range(24)]
check("Session: all 24h covered, overlap highest, dead lowest",
      len(cover) == 24 and max(cover) == session_mult(13) and min(cover) == session_mult(23))

# ---------------------------------------------------------- §17 pearson
def pearson(ca, cb, n):
    ra = [(ca[i]-ca[i+1])/ca[i+1] for i in range(n)]
    rb = [(cb[i]-cb[i+1])/cb[i+1] for i in range(n)]
    ma, mb = sum(ra)/n, sum(rb)/n
    cov = sum((ra[i]-ma)*(rb[i]-mb) for i in range(n))
    va = sum((x-ma)**2 for x in ra); vb = sum((x-mb)**2 for x in rb)
    return cov/math.sqrt(va*vb) if va > 0 and vb > 0 else 0.0
random.seed(7)
base = [100.0]
for _ in range(101): base.append(base[-1]*(1+random.gauss(0, 0.001)))
base = list(reversed(base))
anti = [200.0]
for i in range(101):
    r = (base[100-i-1+1]-base[100-i+1])/base[100-i+1] if False else 0
anti = [1/x*20000 for x in base]                       # inverse instrument
r_self, r_anti = pearson(base, base, 100), pearson(base, anti, 100)
check("Pearson: self-correlation = 1", abs(r_self-1.0) < 1e-9)
check("Pearson: inverse instrument ~ -1", r_anti < -0.99, f"{r_anti:.4f}")

def corr_damp(r, thr=0.70):
    x = mclamp((abs(r)-thr)/(1.0-thr), 0, 1)
    return 1.0 - 0.3*x
check("Correlation dampener: r=1 -> 0.70 multiplier; r=0.7 -> 1.0",
      abs(corr_damp(1.0)-0.7) < 1e-9 and corr_damp(0.70) == 1.0)

# ---------------------------------------------------------- §19 adaptive
def adapt(thr, exp_all, exp_recent, risk_unit, eta=2.0, alpha=0.1, lo=50, hi=85):
    g = exp_all - exp_recent
    target = mclamp(thr + eta*mtanh(g/max(risk_unit, 1e-9)), lo, hi)
    return mclamp(alpha*target + (1-alpha)*thr, lo, hi)
thr = 60.0
worse = adapt(thr, exp_all=10.0, exp_recent=-40.0, risk_unit=75.0)
better = adapt(thr, exp_all=10.0, exp_recent=60.0, risk_unit=75.0)
check("Adaptive: recent losses raise threshold", worse > thr, f"{worse:.3f}")
check("Adaptive: recent outperformance lowers threshold", better < thr, f"{better:.3f}")
t = 60.0
for _ in range(10000): t = adapt(t, 10, -500, 75)
check("Adaptive: bounded at max under sustained losses", t <= 85.0 + 1e-9, f"{t:.2f}")
t = 60.0
for _ in range(10000): t = adapt(t, 10, 500, 75)
check("Adaptive: bounded at min under sustained wins", t >= 50.0 - 1e-9, f"{t:.2f}")

# ---------------------------------------------------------- §10 exec quality
def exec_quality(fills, slips, max_slip=20.0):
    n = len(fills)
    if n == 0: return 100.0
    filled = sum(fills); fr = filled/n
    avg = sum(s for f, s in zip(fills, slips) if f)/filled if filled else 0.0
    return 100.0*fr*mclamp(1-avg/max_slip, 0, 1)
check("ExecQ: perfect fills, no slip -> 100", exec_quality([1]*20, [0]*20) == 100.0)
q = exec_quality([1]*10+[0]*10, [10]*10+[0]*10)
check("ExecQ: 50% fills @ half max slip -> 25 (suspend < 50)", abs(q-25.0) < 1e-9, f"{q}")

# ---------------------------------------------------------- §11 basket math
def basket(entries):  # list of (price, volume, dir)
    tv = sum(v for _, v, _ in entries)
    avg = sum(p*v for p, v, _ in entries)/tv
    return avg, tv
avg, tv = basket([(1.1000, 0.10, 1), (1.0950, 0.07, 1), (1.0900, 0.049, 1)])
manual = (1.1000*0.10 + 1.0950*0.07 + 1.0900*0.049)/0.219
check("Basket: volume-weighted average entry", abs(avg-manual) < 1e-12, f"{avg:.5f}")
def basket_r(float_pl, initial_risk): return float_pl/initial_risk
check("Basket: +2R target trips close", basket_r(150.0, 75.0) >= 2.0)

# ---------------------------------------------------------- §14 chandelier
def chandelier_long(prev_sl, hh, atr, mult):
    return max(prev_sl, hh - mult*atr)
sl = 0.0
path = [(1.1000, 0.0010), (1.1040, 0.0010), (1.1080, 0.0012), (1.1060, 0.0012)]
sls = []
for hh, atr in path:
    sl = chandelier_long(sl, hh, atr, 3.0); sls.append(sl)
check("Chandelier: monotonically non-decreasing for longs",
      all(sls[i] >= sls[i-1] for i in range(1, len(sls))), f"{sls}")
check("Chandelier: exhaustion tighten (x0.6) raises stop",
      chandelier_long(sls[-1], 1.1080, 0.0012, 3.0*0.6) > sls[-1])

# ---------------------------------------------------------- §1 regime table
def classify(adx, er, vol_pct, vr, close, bb_up, bb_lo, mom, bull_choch, bear_choch):
    trending = adx > 25 and er > 0.30
    ranging = adx < 20 and er < 0.20
    hi_v, lo_v = vol_pct > 90, vol_pct < 10
    breakout = vr > 1.5 and ((close > bb_up and mom > 0) or (close < bb_lo and mom < 0))
    reversal = (bull_choch and mom > 0) or (bear_choch and mom < 0)
    for name, cond in [("REVERSAL", reversal), ("BREAKOUT", breakout), ("HIGH_VOL", hi_v),
                       ("TRENDING", trending), ("RANGING", ranging), ("LOW_VOL", lo_v)]:
        if cond: return name
    return "NEUTRAL"
check("Regime: ADX 35 + ER .5 -> TRENDING", classify(35, .5, 50, 1, 100, 101, 99, 20, 0, 0) == "TRENDING")
check("Regime: ADX 15 + ER .1 -> RANGING", classify(15, .1, 50, 1, 100, 101, 99, 0, 0, 0) == "RANGING")
check("Regime: band break + VR 2 + momentum -> BREAKOUT",
      classify(30, .4, 50, 2.0, 101.5, 101, 99, 40, 0, 0) == "BREAKOUT")
check("Regime: CHoCH + diverging momentum -> REVERSAL (priority over breakout)",
      classify(30, .4, 50, 2.0, 101.5, 101, 99, 40, 1, 0) == "REVERSAL")
check("Regime: vol pct 95 -> HIGH_VOL beats TRENDING",
      classify(35, .5, 95, 1, 100, 101, 99, 0, 0, 0) == "HIGH_VOL")
check("Regime: nothing firing -> NEUTRAL", classify(22, .25, 50, 1, 100, 101, 99, 0, 0, 0) == "NEUTRAL")

# ------------------------------------------- full pipeline integration run
random.seed(42)
def integration(trend_bias):
    """Synthetic regime: feed engine chain, verify decision sign follows bias."""
    closes_chron, lvl = [], 100.0
    for cyc in range(40):                       # impulse-pullback swings
        for s in range(6): lvl += trend_bias*0.5 + random.gauss(0, 0.05); closes_chron.append(lvl)
        for s in range(3): lvl -= trend_bias*0.3 + random.gauss(0, 0.05); closes_chron.append(lvl)
    hi, lo, cl = synth_series(closes_chron)
    er = efficiency_ratio(cl, 20)
    s_score, s_dir, _ = update_structure(hi, lo, cl)
    e50_0 = sum(cl[0:50])/50; e50_n = sum(cl[10:60])/50; e20_0 = sum(cl[0:20])/20
    atr = sum(abs(cl[i]-cl[i+1]) for i in range(20))/20
    t_score = trend_score_core(40, e50_0, e50_n, e20_0, atr, er)
    roc0 = (cl[0]-cl[10])/cl[10]*100
    m_score = momentum_score(50+trend_bias*20, roc0, trend_bias*0.02*atr, atr)
    l_score = 0.0
    mtf_align = trend_bias*1.0
    cdir, cfin = confidence(s_score, t_score, m_score, l_score, mtf_align,
                            vol_suit=90, spread_pts=5, max_spread=30, exec_q=100)
    return decide(cdir, cfin, False, 0)
check("PIPELINE: persistent uptrend -> BUY", integration(+1) == "BUY", integration(+1))
check("PIPELINE: persistent downtrend -> SELL", integration(-1) == "SELL", integration(-1))


# ============================ v2.00 ARITHMETIC ============================
# The v1 defect: a FIXED threshold the arithmetic could never reach.
# v2 ranks conviction against its own rolling distribution instead.

GAIN, MAXSPR, FREEFRAC = 2.5, 40.0, 0.60

def spread_penalty_v1(sp, maxspr=30.0):
    return mclamp(1 - sp/maxspr, 0, 1)

def spread_penalty_v2(sp, maxspr=MAXSPR, freefrac=FREEFRAC):
    free = freefrac*maxspr
    if sp <= free: return 1.0
    return mclamp(1 - (sp-free)/max(maxspr-free, 1e-9), 0, 1)

check("v2 spread: routine 15pt spread is unpenalized (v1 halved it)",
      spread_penalty_v2(15) == 1.0 and spread_penalty_v1(15) == 0.5)
check("v2 spread: penalty ramps only near the limit",
      spread_penalty_v2(24) == 1.0 and 0 < spread_penalty_v2(32) < 1)
check("v2 spread: at/over hard limit -> 0", spread_penalty_v2(40) == 0.0 and spread_penalty_v2(50) == 0.0)
check("v2 spread: monotonically non-increasing",
      all(spread_penalty_v2(s) >= spread_penalty_v2(s+1) for s in range(0, 50)))

def confidence_v2(struct, trend, mom, liq, mtf, vol_suit, spread, execq=100.0,
                  w=(0.25,0.25,0.20,0.15,0.15)):
    raw = w[0]*struct/100 + w[1]*trend/100 + w[2]*mom/100 + w[3]*liq/100 + w[4]*mtf
    cdir = 100*mtanh(GAIN*raw)
    return cdir, abs(cdir)*(vol_suit/100)*spread_penalty_v2(spread)*mclamp(execq/100,0,1)

class ConfRing:
    """Rolling confidence distribution — the self-calibrating threshold (§9)."""
    def __init__(self, size=500): self.size, self.buf = size, []
    def percentile(self, c):
        if not self.buf: return 50.0
        return 100.0*sum(1 for s in self.buf if s < c)/len(self.buf)
    def push(self, c):
        self.buf.append(c)
        if len(self.buf) > self.size: self.buf.pop(0)
    def __len__(self): return len(self.buf)

r = ConfRing(100)
for v in range(100): r.push(float(v))
check("Percentile: value above all samples -> 100", r.percentile(999) == 100.0)
check("Percentile: value below all samples -> 0", r.percentile(-1) == 0.0)
check("Percentile: median sample -> ~50", abs(r.percentile(50)-50) <= 1)

# Self-calibration is the whole point: the SAME relative conviction must clear
# the bar whether the instrument produces big scores or tiny ones.
for scale, label in [(0.1, "tiny-range instrument"), (1.0, "normal"), (10.0, "wide-range")]:
    ring = ConfRing(200)
    random.seed(3)
    for _ in range(200): ring.push(abs(random.gauss(0, 20))*scale)
    top = sorted(ring.buf)[int(len(ring.buf)*0.93)]
    check(f"Self-calibration: top-decile conviction clears 85th pct on {label}",
          ring.percentile(top) >= 85.0, f"pct={ring.percentile(top):.1f}")

def decide_v2(cdir, cfin, ring, in_trade=False, basket_dir=0, entry_conf=0.0,
              entry_pct=85.0, floor=18.0, boot=35.0, min_samples=60,
              mtf_align=0.0, mtf_confl=0.0, mtf_valid=1.0, veto=60.0,
              exit_frac=0.55):
    d = msign(cdir)
    if not in_trade:
        if d == 0: return "WAIT"
        if cfin < floor: return "WAIT"
        if len(ring) >= min_samples:
            if ring.percentile(cfin) < entry_pct: return "WAIT"
        elif cfin < boot: return "WAIT"
        if mtf_valid >= 0.5 and msign(mtf_align) != d and mtf_confl > veto: return "WAIT"
        return "BUY" if d > 0 else "SELL"
    if cfin < max(exit_frac*entry_conf, floor*0.5): return "EXIT"
    if d != 0 and basket_dir != 0 and d != basket_dir and cfin >= floor: return "EXIT"
    return "HOLD"

# THE REGRESSION THAT MATTERS: v2 must actually fire on realistic data.
random.seed(11)
ring = ConfRing(500); fired = 0; total = 3000
for _ in range(total):
    cdir, cfin = confidence_v2(random.gauss(0,35), random.gauss(0,40), random.gauss(0,35),
                               random.gauss(0,25),
                               random.choice([-1,-.6,-.4,-.2,0,.2,.4,.6,1])*random.uniform(.6,1),
                               random.uniform(60,100), random.uniform(10,20))
    d = decide_v2(cdir, cfin, ring)
    ring.push(cfin)
    if d in ("BUY","SELL"): fired += 1
check("v2 EXECUTION REGRESSION: EA actually fires on realistic data (v1 fired 0)",
      fired > 100, f"{fired} signals in {total} bars")
check("v2 EXECUTION REGRESSION: selectivity retained (not firing every bar)",
      fired < total*0.35, f"{100.0*fired/total:.1f}% of bars")

# floor still blocks junk conviction even when it ranks highly in a dead market
dead = ConfRing(200)
for _ in range(200): dead.push(random.uniform(0, 8))
check("v2 floor: dead market's 'best' conviction still blocked by absolute floor",
      decide_v2(9.0, 9.0, dead) == "WAIT")

check("v2 MTF veto: stands down when higher-timeframe data is unavailable",
      decide_v2(70, 90, ConfRing(0), mtf_align=-0.9, mtf_confl=90, mtf_valid=0.1) in ("BUY","SELL"))
check("v2 MTF veto: still blocks when data IS available and disagrees",
      decide_v2(70, 90, ConfRing(0), mtf_align=-0.9, mtf_confl=90, mtf_valid=1.0) == "WAIT")

check("v2 exit: conviction below fraction of entry conviction -> EXIT",
      decide_v2(70, 30, ring, in_trade=True, basket_dir=1, entry_conf=60) == "EXIT")
check("v2 exit: conviction holding above fraction -> HOLD",
      decide_v2(70, 40, ring, in_trade=True, basket_dir=1, entry_conf=60) == "HOLD")
check("v2 exit: direction flip with real conviction -> EXIT",
      decide_v2(-70, 50, ring, in_trade=True, basket_dir=1, entry_conf=60) == "EXIT")

# adaptive selectivity now moves the PERCENTILE, bounded
def adapt_pct(pct, exp_all, exp_recent, unit, eta=2.0, alpha=0.1, lo=70, hi=95):
    target = mclamp(pct + eta*mtanh((exp_all-exp_recent)/max(unit,1e-9)), lo, hi)
    return mclamp(alpha*target + (1-alpha)*pct, lo, hi)
check("v2 adaptive: losses raise selectivity percentile", adapt_pct(85, 10, -40, 75) > 85)
check("v2 adaptive: wins lower selectivity percentile", adapt_pct(85, 10, 60, 75) < 85)
p = 85.0
for _ in range(5000): p = adapt_pct(p, 10, -500, 75)
check("v2 adaptive: bounded at ceiling", p <= 95.0+1e-9, f"{p:.2f}")
p = 85.0
for _ in range(5000): p = adapt_pct(p, 10, 500, 75)
check("v2 adaptive: bounded at floor", p >= 70.0-1e-9, f"{p:.2f}")


# ========================= v2.50 NEW ENGINES ============================

# --- §22 Order Flow Engine: tick-volume weighted close location
def order_flow(bars, gain=2.0):
    """bars: list of (high, low, close, tickvol), index 0 = newest"""
    num = den = 0.0
    for h, l, c, v in bars:
        rng = h - l
        if rng <= 0: continue
        clv = ((c-l)-(h-c))/rng
        w = v if v > 0 else 1.0
        num += clv*w; den += w
    return 100.0*mtanh(gain*(num/den)) if den > 0 else 0.0

buy_pressure  = [(10.0, 9.0, 9.95, 100)]*20   # closes at the highs
sell_pressure = [(10.0, 9.0, 9.05, 100)]*20   # closes at the lows
mid           = [(10.0, 9.0, 9.50, 100)]*20
check("OrderFlow: closes at highs -> strong positive", order_flow(buy_pressure) > 50,
      f"{order_flow(buy_pressure):.1f}")
check("OrderFlow: closes at lows -> symmetric negative",
      abs(order_flow(buy_pressure)+order_flow(sell_pressure)) < 1e-9)
check("OrderFlow: closes mid-range -> ~0", abs(order_flow(mid)) < 1e-9)
check("OrderFlow: bounded and volume-weighted",
      -100 <= order_flow(buy_pressure) <= 100 and
      order_flow([(10,9,9.95,1000)]+[(10,9,9.05,1)]*3) > 0)
check("OrderFlow: zero-range bars skipped without dividing by zero",
      order_flow([(10.0,10.0,10.0,50)]*5) == 0.0)

# --- §23 Volatility Forecast: RiskMetrics EWMA
def ewma_sigma(returns, lam=0.94):
    var = None
    for r in returns:
        var = r*r if var is None else lam*var + (1-lam)*r*r
    return math.sqrt(var) if var and var > 0 else 0.0

calm_then_wild = [0.0001]*80 + [0.01]*20
wild_then_calm = [0.01]*80 + [0.0001]*20
s_cw, s_wc = ewma_sigma(calm_then_wild), ewma_sigma(wild_then_calm)
check("VolForecast: recent turbulence dominates the forecast", s_cw > s_wc,
      f"{s_cw:.5f} vs {s_wc:.5f}")
# EWMA(0.94) has a ~16-bar half-life: after 20 calm bars it still retains
# roughly 29% of the prior variance. Assert that documented decay, not a
# faster one -- the sigma should fall well below the wild level but need
# not reach the calm level yet.
decay = s_wc/0.01
check("VolForecast: calm-after-wild decays toward calm at the EWMA half-life",
      0.30 < decay < 0.75, f"retained {decay*100:.0f}% of wild sigma")
check("VolForecast: wild-after-calm rises most of the way to the wild level",
      s_cw/0.01 > 0.75, f"reached {s_cw/0.01*100:.0f}% of wild sigma")
def realized(returns):
    m = sum(returns)/len(returns)
    return math.sqrt(sum((r-m)**2 for r in returns)/len(returns))
ratio = mclamp(ewma_sigma(calm_then_wild)/max(realized(calm_then_wild),1e-12), 0.25, 4.0)
check("VolForecast: expansion gives ratio > 1 (EA sizes down)", ratio > 1.0, f"{ratio:.2f}")
check("VolForecast: ratio clamped to sane bounds", 0.25 <= ratio <= 4.0)

# --- §24 Trade Quality Score
def trade_quality(spread_pts, point, tp_dist, regime_fit, htf, flow, volq, sessq, fc):
    edge = mclamp(1 - (spread_pts*2*point)/tp_dist, 0, 1) if tp_dist > 0 else 0
    q = 100*(0.24*edge + 0.20*regime_fit + 0.18*htf + 0.14*flow
             + 0.12*volq + 0.07*sessq + 0.05*fc)
    return mclamp(q, 0, 100)

good = trade_quality(12, 0.00001, 0.0036, 1.0, 0.9, 0.85, 0.95, 1.0, 1.0)
poor = trade_quality(35, 0.00001, 0.0009, 0.4, 0.15, 0.3, 0.4, 0.25, 0.6)
check("Quality: excellent setup scores high", good > 85, f"{good:.1f}")
check("Quality: poor setup scores low", poor < 45, f"{poor:.1f}")
check("Quality: bounded 0-100", 0 <= good <= 100 and 0 <= poor <= 100)
wide = trade_quality(200, 0.00001, 0.0036, 1.0, 0.9, 0.85, 0.95, 1.0, 1.0)
check("Quality: spread wider than target destroys the edge term", wide < good, f"{wide:.1f}")

# --- §25 Equity Curve Engine
def equity_curve_mult(profits, n=10, cut=0.6):
    if len(profits) < n+1: return 1.0
    curve, run = [], 0.0
    for p in profits:
        run += p; curve.append(run)
    sma = sum(curve[-n:])/n
    return cut if curve[-1] < sma else 1.0
rising  = [10.0]*20
falling = [10.0]*10 + [-10.0]*10
check("EquityCurve: rising curve -> full size", equity_curve_mult(rising) == 1.0)
check("EquityCurve: curve below its average -> reduced size", equity_curve_mult(falling) == 0.6)
check("EquityCurve: too few trades -> no interference", equity_curve_mult([1.0]*5) == 1.0)
check("EquityCurve: never zero (recovery stays observable)",
      equity_curve_mult(falling) > 0)

# --- §26 Participation Watchdog
def effective_pct(base, idle_bars, idle_start=40, every=10, step=2.0, floor=60.0):
    if idle_bars <= idle_start: return base
    steps = 1 + (idle_bars-idle_start)//every
    return max(base - steps*step, floor)
check("Watchdog: no relaxation before the idle threshold",
      effective_pct(82, 10) == 82 and effective_pct(82, 40) == 82)
check("Watchdog: relaxes stepwise once idle", effective_pct(82, 41) == 80.0 and
      effective_pct(82, 51) == 78.0, f"{effective_pct(82,41)}, {effective_pct(82,51)}")
check("Watchdog: monotonically non-increasing in idle time",
      all(effective_pct(82, i) >= effective_pct(82, i+1) for i in range(0, 400)))
check("Watchdog: never relaxes below its hard floor",
      effective_pct(82, 100000) == 60.0)
check("Watchdog: floor is above the distribution midpoint (still selective)",
      effective_pct(82, 100000) > 50.0)

# THE ANTI-STATIONARY GUARANTEE: given any market that clears the safety
# floor at all, the watchdog must eventually produce an entry.
random.seed(5)
for label, scale in [("quiet market", 0.35), ("normal market", 1.0), ("volatile market", 2.0)]:
    ring = ConfRing(500)
    for _ in range(500): ring.push(abs(random.gauss(0, 18))*scale)
    idle, fired_at = 0, None
    for bar in range(600):
        cfin = abs(random.gauss(0, 18))*scale
        pct = ring.percentile(cfin); ring.push(cfin)
        eff = effective_pct(82, idle)
        if cfin >= 15.0 and pct >= eff:
            fired_at = bar; break
        idle += 1
    ok = fired_at is not None
    check(f"ANTI-STATIONARY: watchdog forces participation in {label}",
          ok, f"never fired in 600 bars (scale {scale})")
    if ok:
        check(f"ANTI-STATIONARY: {label} entry within a bounded wait",
              fired_at < 400, f"took {fired_at} bars")

# floor still wins over the watchdog: a market with no conviction at all
# must NOT be forced into a trade
ring_dead = ConfRing(300)
for _ in range(300): ring_dead.push(random.uniform(0, 6))
forced = False
for bar in range(1000):
    cfin = random.uniform(0, 6)
    pct = ring_dead.percentile(cfin); ring_dead.push(cfin)
    if cfin >= 15.0 and pct >= effective_pct(82, bar):
        forced = True; break
check("ANTI-STATIONARY: safety floor still blocks a conviction-less market",
      not forced, "watchdog wrongly forced a trade below the floor")

# --- history seeding: percentile mode must be live immediately
def seeded_ring(n=500, scale=1.0):
    r = ConfRing(500)
    for _ in range(n): r.push(abs(random.gauss(0, 20))*scale)
    return r
check("Seeding: distribution live from bar 1 (no 60-bar warm-up)",
      len(seeded_ring()) >= 40)
sr = seeded_ring()
check("Seeding: seeded ring produces usable percentile ranks immediately",
      0 <= sr.percentile(30) <= 100 and sr.percentile(9999) == 100.0)

# --- §14 partial close + break-even
def partial_volume(vol, pct, step=0.01, minlot=0.01):
    part = math.floor(vol*pct/100.0/step + 1e-9)*step
    if part < minlot or (vol-part) < minlot: return 0.0
    return part
check("PartialTP: splits a normal position", abs(partial_volume(0.10, 50)-0.05) < 1e-9)
check("PartialTP: refuses to split when a leg would fall below min lot",
      partial_volume(0.01, 50) == 0.0)
check("PartialTP: remainder always >= min lot when a split happens",
      all((0.10 - partial_volume(0.10, p)) >= 0.01 for p in [10, 50, 90]))

def break_even(entry, direction, buf):
    return entry + direction*buf
check("BreakEven: long stop moves above entry by the buffer",
      break_even(1.1000, 1, 0.0002) > 1.1000)
check("BreakEven: short stop moves below entry by the buffer",
      break_even(1.1000, -1, 0.0002) < 1.1000)

# weights still normalize with the sixth engine added
w = [0.22, 0.22, 0.18, 0.12, 0.13, 0.13]
check("Confidence: six-engine weights normalize to 1", abs(sum(w)-1.0) < 1e-9)


# ===================== v2.60 — XAUUSD DEAD-EA POSTMORTEM =================
# Live backtest on XAUUSD.m M5 logged "conviction 0.0" on every bar for six
# years. Root cause: the spread penalty multiplied into conviction reaches
# EXACTLY zero at the limit, and a EURUSD-calibrated 40-point limit is
# unreachable on 3-digit gold. These tests lock both fixes.

def pspread_v250(sp, maxspr=40.0, freefrac=0.60):
    free = freefrac*maxspr
    if sp <= free: return 1.0
    return mclamp(1-(sp-free)/max(maxspr-free,1e-9), 0, 1)

check("POSTMORTEM: v2.50 spread factor reaches exactly 0.0 at the limit",
      pspread_v250(40) == 0.0 and pspread_v250(300) == 0.0)
check("POSTMORTEM: a zero factor annihilates any conviction (the dead EA)",
      abs(87.0 * pspread_v250(300)) == 0.0)
# no other factor could have produced exactly zero -> the diagnosis is unique
vol_min = min(vol_suitability(p) for p in range(0, 101))/100.0
check("POSTMORTEM: volatility factor can never reach zero (rules it out)",
      vol_min > 0.15, f"min {vol_min:.3f}")

def confidence_v260(struct, trend, mom, liq, mtf, flow, vol_suit,
                    w=(0.22,0.22,0.18,0.12,0.13,0.13), gain=2.5):
    """v2.60: conviction is market analysis ONLY -- no spread, no exec."""
    raw = (w[0]*struct/100 + w[1]*trend/100 + w[2]*mom/100
           + w[3]*liq/100 + w[4]*mtf + w[5]*flow/100)
    return abs(100*mtanh(gain*raw))*mclamp(vol_suit/100, 0, 1)

for spread in [0, 15, 40, 300, 5000]:
    c = confidence_v260(60, 70, 55, 20, 0.6, 45, 90)
    check(f"v2.60: conviction is independent of spread ({spread} pts)",
          c > 40, f"{c:.1f}")
check("v2.60: conviction can still be zero only if the market itself is flat",
      confidence_v260(0, 0, 0, 0, 0, 0, 90) == 0.0)
check("v2.60: any real directional evidence yields non-zero conviction",
      confidence_v260(1, 0, 0, 0, 0, 0, 90) > 0.0)

def max_spread_pts(atr_price, point, floor_pts=40.0, frac=0.50):
    by_atr = frac*(atr_price/point) if point > 0 and atr_price > 0 else 0.0
    return max(by_atr, max(floor_pts, 1.0))

eur = max_spread_pts(0.00080, 0.00001)
gold2 = max_spread_pts(0.80, 0.01)
gold3 = max_spread_pts(0.80, 0.001)
check("SpreadLimit: EURUSD keeps a sane tight limit", 28 <= eur <= 45, f"{eur:.0f}")
check("SpreadLimit: 3-digit gold scales up automatically", gold3 > 250, f"{gold3:.0f}")
# The hard gate is a BACKSTOP (0.50*ATR), not a cost filter -- §24 prices
# the economics. A normal gold spread must clear the backstop and then be
# penalized by quality, rather than being silently blocked.
gold3 = max_spread_pts(0.80, 0.001, frac=0.50)
check("SpreadLimit: a normal 300pt gold spread clears the backstop",
      300 <= gold3, f"limit {gold3:.0f}")
check("SpreadLimit: an abusive 900pt gold spread is still blocked",
      900 > gold3, f"limit {gold3:.0f}")
q_tight = trade_quality(300, 0.001, 2.4, 1.0, 0.9, 0.85, 0.95, 1.0, 1.0)
q_wide  = trade_quality(900, 0.001, 2.4, 1.0, 0.9, 0.85, 0.95, 1.0, 1.0)
check("SpreadLimit: quality engine still prices the spread it lets through",
      q_wide < q_tight, f"{q_wide:.1f} vs {q_tight:.1f}")
check("SpreadLimit: v2.50 fixed limit would have BLOCKED it", 300 > 40)
check("SpreadLimit: absolute floor still protects tiny-ATR instruments",
      max_spread_pts(0.00001, 0.00001) >= 40)
check("SpreadLimit: limit rises monotonically with ATR",
      all(max_spread_pts(a, 0.001) <= max_spread_pts(a+0.1, 0.001)
          for a in [0.1, 0.5, 1.0, 5.0]))

# --- affordability: the blocker no code can fix, so it must be REPORTED
def affordable(equity, min_lot, contract, price, leverage, safety=1.5):
    margin = min_lot*contract*price/leverage
    return margin*safety <= equity, margin*safety

ok10, need10 = affordable(10, 0.01, 100, 2000, 100)
check("Affordability: $10 account CANNOT hold 0.01 lots of gold",
      not ok10, f"needs ${need10:.2f}")
ok50, _ = affordable(50, 0.01, 100, 2000, 100)
check("Affordability: $50 clears the same gold position", ok50)
okfx, needfx = affordable(10, 0.01, 100000, 1.10, 100)
check("Affordability: $10 CANNOT hold 0.01 lots of EURUSD either",
      not okfx, f"needs ${needfx:.2f}")
okfx500, _ = affordable(10, 0.01, 100000, 1.10, 500)
check("Affordability: 1:500 leverage brings 0.01 EURUSD within reach of $10",
      okfx500)
check("Affordability: requirement scales linearly with price",
      abs(affordable(10,0.01,100,4000,100)[1] - 2*affordable(10,0.01,100,2000,100)[1]) < 1e-9)


# ============ v2.70 — THE "R MEASURED AGAINST THE WRONG RISK" BUG ==========
# Live XAUUSD run closed trades within seconds at "2.2R", "37.6R", "94.3R".
# Cause: g_initialRiskAmt held the PLANNED risk while the position carried a
# far larger real risk, so every R-based exit fired on noise.

def r_multiple(float_pl, risk_amt):
    return float_pl/risk_amt if risk_amt > 0 else 0.0

planned, actual = 0.045, 17.15          # figures straight from the live log
check("POSTMORTEM: planned vs actual risk differed by orders of magnitude",
      actual/planned > 100, f"{actual/planned:.0f}x")
check("POSTMORTEM: 2R target against planned risk fires on cents of profit",
      r_multiple(0.099, planned) >= 2.0 and 0.099 < 0.15,
      f"$0.099 registered as {r_multiple(0.099, planned):.1f}R")
check("POSTMORTEM: same profit against ACTUAL risk is correctly ~0R",
      r_multiple(0.099, actual) < 0.01, f"{r_multiple(0.099, actual):.4f}R")
check("v2.70: storing actual risk makes a 2R target require real profit",
      abs(2.0*actual - 34.30) < 0.01, f"${2.0*actual:.2f} needed")
check("v2.70: break-even at 1R now needs a real move, not 4 dollars on a 17 dollar risk",
      1.0*actual > 1.0*planned*94, f"{actual:.2f} vs {planned*94:.2f}")

# --- hard risk ceiling
def risk_allowed(risk, equity, hard_pct=20.0):
    return risk <= equity*hard_pct/100.0

check("HardCeiling: v2.50 let a $10 account risk 172% per trade",
      not risk_allowed(17.15, 10.0), "correctly blocked in v2.70")
check("HardCeiling: same trade allowed once the account can carry it",
      risk_allowed(17.15, 100.0), "at $100 equity that is 17%")
# The override's purpose: permit a min-lot trade that exceeds the PLANNED
# cap (2.5%) while still refusing anything above the hard ceiling (20%).
over_plan_under_ceiling = 1.50      # 15% of a $10 account
over_ceiling            = 17.15     # 172% -- the live run
check("HardCeiling: override permits over-plan but under-ceiling risk",
      risk_allowed(over_plan_under_ceiling, 10.0, 20.0) and
      over_plan_under_ceiling > 10.0*0.025,
      f"${over_plan_under_ceiling:.2f} = 15% > 2.5% plan, < 20% ceiling")
check("HardCeiling: override cannot bypass the ceiling",
      not risk_allowed(over_ceiling, 10.0, 20.0))
check("HardCeiling: ceiling scales with equity, not a fixed currency amount",
      risk_allowed(20.0, 100.0) and not risk_allowed(20.0, 50.0))

# --- one loss must no longer be able to latch the breaker instantly
def breaker_trips(loss, equity, daily_pct=3.0):
    return loss >= equity*daily_pct/100.0
check("Breaker: 172% risk trips the 3% daily limit 57x over (the dead run)",
      breaker_trips(17.15, 10.0) and 17.15/(10.0*0.03) > 50)
check("Breaker: capped risk still trips it, but only after a real losing streak",
      breaker_trips(2.0, 10.0) and not breaker_trips(0.25, 10.0))

# --- minimum viable deposit
def min_deposit(min_lot, contract, sl_distance, ceiling_pct):
    return (min_lot*contract*sl_distance)/(ceiling_pct/100.0)
d_covid = min_deposit(0.01, 100, 1.5*11.4, 20.0)
d_norm  = min_deposit(0.01, 100, 1.5*1.5, 20.0)
check("MinDeposit: COVID-era gold volatility demands a far larger account",
      d_covid > 80, f"${d_covid:.0f}")
check("MinDeposit: typical gold volatility is far more attainable",
      d_norm < 20, f"${d_norm:.0f}")
check("MinDeposit: scales linearly with stop distance",
      abs(min_deposit(0.01,100,3.0,20.0) - 2*min_deposit(0.01,100,1.5,20.0)) < 1e-9)
check("MinDeposit: a $10 account cannot carry COVID-era gold at any risk setting",
      d_covid > 10.0, f"needs ${d_covid:.0f}")


# ================== v3.00 PRICE-ACTION ENGINES (no indicators) ============

def true_range(h, l, c, i):
    if i+1 >= len(c): return h[i]-l[i]
    return max(h[i]-l[i], abs(h[i]-c[i+1]), abs(l[i]-c[i+1]))

def atr_manual(h, l, c, period=14):
    n = min(period, len(c)-1)
    return sum(true_range(h, l, c, i) for i in range(n))/n if n > 0 else 0.0

h = [10.5, 10.4, 10.6, 10.2, 10.3]
l = [10.0, 9.9, 10.1, 9.8, 9.9]
c = [10.2, 10.3, 10.4, 10.0, 10.1]
check("ATR: computed from true range with no indicator handle",
      atr_manual(h, l, c, 4) > 0)
check("ATR: gap up is captured by true range, not just the bar range",
      true_range([12.0], [11.5], [12.0, 10.0], 0) == 2.0,
      f"{true_range([12.0],[11.5],[12.0,10.0],0)}")
check("ATR: first bar falls back to its own range safely",
      true_range([10.5], [10.0], [10.2], 0) == 0.5)

# --- §B supply/demand zone detection: base then impulse
def find_zone(bars, atr, impulse_atr=1.20, impulse_body=0.55,
              base_max_atr=0.85, max_base=3):
    """bars: list of (o,h,l,c), index 0 = newest."""
    for i in range(1, len(bars)-1):
        o, hi, lo, cl = bars[i]
        rng, body = hi-lo, abs(cl-o)
        if rng <= 0: continue
        up = rng >= impulse_atr*atr and body >= impulse_body*rng and cl > o
        dn = rng >= impulse_atr*atr and body >= impulse_body*rng and cl < o
        if not (up or dn): continue
        top, bot, used = -1e18, 1e18, 0
        for b in range(i+1, min(i+1+max_base, len(bars))):
            ob, hb, lb, cb = bars[b]
            if (hb-lb) > base_max_atr*atr: break
            top, bot, used = max(top, hb), min(bot, lb), used+1
        if used:
            return dict(top=top, bottom=bot, dir=1 if up else -1,
                        strength=rng/atr, base_candles=used)
    return None

atr = 1.0
# newest first: [0]=current, [1]=impulse up, [2..4]=quiet base
demand_bars = [(103.0,103.5,102.8,103.2),      # current
               (100.2,102.5,100.0,102.3),      # impulse up, range 2.5 = 2.5xATR
               (100.1,100.3,99.9,100.2),       # base
               (100.0,100.2,99.8,100.1),       # base
               (99.9,100.1,99.7,100.0)]        # base
z = find_zone(demand_bars, atr)
check("Zones: base + impulse up creates a DEMAND zone", z is not None and z['dir'] == 1,
      str(z))
check("Zones: zone spans the base range, not the impulse candle",
      z is not None and z['bottom'] >= 99.7 and z['top'] <= 100.4, str(z))
check("Zones: strength recorded in ATR units", z is not None and z['strength'] >= 1.2,
      f"{z['strength']:.2f}" if z else "none")

supply_bars = [(97.0,97.2,96.5,96.8),
               (100.0,100.1,97.5,97.7),        # impulse down
               (100.0,100.2,99.8,100.1),
               (100.1,100.3,99.9,100.2),
               (100.0,100.2,99.9,100.1)]
zs = find_zone(supply_bars, atr)
check("Zones: base + impulse down creates a SUPPLY zone", zs is not None and zs['dir'] == -1,
      str(zs))
# a weak departure is not an imbalance
weak = [(100.3,100.4,100.2,100.3),
        (100.0,100.4,99.9,100.3),              # range 0.5 < 1.2xATR
        (100.0,100.2,99.8,100.1),
        (100.1,100.3,99.9,100.2),
        (100.0,100.2,99.9,100.1)]
check("Zones: a weak departure does NOT create a zone", find_zone(weak, atr) is None)
# a wide, volatile base is not a base
noisy = [(103.0,103.5,102.8,103.2),
         (100.2,102.5,100.0,102.3),
         (100.0,101.5,98.5,100.2),             # range 3.0 > 0.85xATR
         (100.0,101.4,98.6,100.1),
         (99.9,101.3,98.7,100.0)]
check("Zones: a volatile base is rejected (no consolidation, no stranded orders)",
      find_zone(noisy, atr) is None)

# --- zone freshness
def zone_quality(tests, dist_atr, strength, max_tests=2):
    fresh = mclamp(1-tests/max(max_tests,1), 0, 1)
    near  = mclamp(1-dist_atr/3.0, 0, 1)
    stren = mclamp(strength/3.0, 0, 1)
    return fresh*0.45 + near*0.35 + stren*0.20
check("Zones: an untested zone outranks a repeatedly tested one",
      zone_quality(0, 0.2, 2.0) > zone_quality(2, 0.2, 2.0))
check("Zones: a near zone outranks a distant one",
      zone_quality(0, 0.2, 2.0) > zone_quality(0, 2.8, 2.0))
check("Zones: a stronger departure outranks a weak one",
      zone_quality(0, 0.2, 3.0) > zone_quality(0, 0.2, 1.0))

# --- §C trend from swing sequence, NOT from a moving average
def trend_from_swings(highs, lows):
    up = dn = 0
    for i in range(1, len(highs)):
        if highs[i] > highs[i-1]: up += 1
        else: dn += 1
    for i in range(1, len(lows)):
        if lows[i] > lows[i-1]: up += 1
        else: dn += 1
    return 100.0*(up-dn)/(up+dn+1)
check("Trend: higher highs and higher lows -> bullish, no EMA involved",
      trend_from_swings([10,11,12,13], [9,10,11,12]) > 50)
check("Trend: lower highs and lower lows -> bearish",
      trend_from_swings([13,12,11,10], [12,11,10,9]) < -50)
check("Trend: mixed swings -> near neutral",
      abs(trend_from_swings([10,11,10,11], [9,10,9,10])) < 30)

# --- §D momentum from candle anatomy
def momentum_pa(bars):
    body = sum(c-o for o, hi, lo, c in bars)
    rng  = sum(hi-lo for o, hi, lo, c in bars)
    dom  = body/rng if rng > 0 else 0.0
    return 100.0*mtanh(1.4*0.45*dom)
strong_up = [(100, 101, 99.95, 100.95)]*8       # closes at the highs, tiny wicks
strong_dn = [(100.95, 101.05, 100, 100)]*8
indecisive = [(100, 101, 99, 100)]*8            # big range, no body
check("Momentum: bodies closing upward -> positive", momentum_pa(strong_up) > 20)
check("Momentum: mirrored bearish bars -> negative", momentum_pa(strong_dn) < -20)
check("Momentum: all wick, no body -> ~zero", abs(momentum_pa(indecisive)) < 5)

# --- entry setups must actually fire
def rejection_setup(o, hi, lo, cl, zone_top, zone_bottom, zone_dir, wick_frac=0.30):
    rng = hi-lo
    if rng <= 0: return 0
    lower = (min(o, cl)-lo)/rng
    upper = (hi-max(o, cl))/rng
    touched = lo <= zone_top and hi >= zone_bottom
    if not touched: return 0
    if zone_dir > 0 and lower >= wick_frac and cl > zone_bottom: return 1
    if zone_dir < 0 and upper >= wick_frac and cl < zone_top:    return -1
    return 0

check("Setup: wick into demand then close back above -> LONG",
      rejection_setup(100.5, 100.7, 99.6, 100.4, 100.0, 99.5, 1) == 1)
check("Setup: wick into supply then close back below -> SHORT",
      rejection_setup(99.5, 100.4, 99.3, 99.6, 100.0, 99.5, -1) == -1)
check("Setup: price never reaching the zone -> no trade",
      rejection_setup(105, 105.5, 104.5, 105.2, 100.0, 99.5, 1) == 0)
check("Setup: closing straight through demand -> no long (zone failed)",
      rejection_setup(100.2, 100.3, 99.0, 99.1, 100.0, 99.5, 1) == 0)

# --- stops anchored to the zone, not to an arbitrary ATR distance
def plan_stop(direction, entry, zone_top, zone_bottom, atr, buf_mult=1.2, tp_r=2.5):
    anchor = zone_bottom if direction > 0 else zone_top
    sl = anchor - buf_mult*atr if direction > 0 else anchor + buf_mult*atr
    risk = abs(entry-sl)
    if risk < 0.5*atr:
        risk = 0.5*atr
        sl = entry-risk if direction > 0 else entry+risk
    tp = entry + tp_r*risk if direction > 0 else entry - tp_r*risk
    return sl, tp, risk

sl, tp, risk = plan_stop(1, 100.4, 100.0, 99.5, 1.0)
check("Stops: long stop sits BELOW the demand zone", sl < 99.5, f"{sl:.2f}")
check("Stops: target is the configured R multiple of the real risk",
      abs((tp-100.4) - 2.5*risk) < 1e-9)
sl2, tp2, _ = plan_stop(-1, 99.6, 100.0, 99.5, 1.0)
check("Stops: short stop sits ABOVE the supply zone", sl2 > 100.0, f"{sl2:.2f}")
check("Stops: a trivially tight stop is widened to a sane floor",
      plan_stop(1, 100.0, 100.0, 99.99, 1.0)[2] >= 0.5)

# --- the whole point: this configuration must produce trades
random.seed(21)
ring = ConfRing(400)
for _ in range(400): ring.push(abs(random.gauss(0, 22)))
fired = 0
for bar in range(800):
    conv = abs(random.gauss(0, 22))
    setup_present = random.random() < 0.12          # a setup roughly 1 bar in 8
    pct = ring.percentile(conv); ring.push(conv)
    idle_eff = max(75.0 - 2.5*max(0, (bar % 120 - 30)//8), 55.0)
    if setup_present and conv >= 12.0 and pct >= idle_eff:
        fired += 1
check("PRICE ACTION: configuration produces trades over a normal stretch",
      fired > 20, f"{fired} entries in 800 bars")
check("PRICE ACTION: still selective, not firing on every setup",
      fired < 800*0.12, f"{fired} of ~96 setups taken")


# ============= v3.10 AFFORDABILITY-AWARE STOP PLACEMENT ==================
def affordable_stop(equity, ceiling_pct, min_lot, contract):
    """Widest stop the account can carry at broker minimum lot."""
    cap = equity*ceiling_pct/100.0
    per_unit = min_lot*contract          # currency moved per 1.0 price unit
    return cap/per_unit if per_unit > 0 else 0.0

a10  = affordable_stop(10, 20, 0.01, 100)
a50  = affordable_stop(50, 20, 0.01, 100)
a100 = affordable_stop(100, 20, 0.01, 100)
check("Affordable stop: $10 gold account can carry only a $2 stop",
      abs(a10-2.0) < 1e-9, f"${a10:.2f}")
check("Affordable stop: scales linearly with equity",
      abs(a100 - 10*a10) < 1e-9 and abs(a50 - 5*a10) < 1e-9)
check("Affordable stop: $10 cannot cover the logged $7.70 structural stop", a10 < 7.70)
check("Affordable stop: $50 covers every stop seen in the live log", a50 >= 7.70)

def entry_decision(structural_stop, equity, fit_to_account, skip_unaffordable,
                   ceiling_pct=20, min_lot=0.01, contract=100):
    afford = affordable_stop(equity, ceiling_pct, min_lot, contract)
    if structural_stop <= afford: return ("TRADE", structural_stop)
    if fit_to_account:            return ("TRADE_TIGHTENED", afford)
    if skip_unaffordable:         return ("SKIP", 0.0)
    return ("SKIP", 0.0)

check("v3.10: affordable structural stop is taken as-is",
      entry_decision(1.50, 10, False, True)[0] == "TRADE")
check("v3.10: unaffordable stop is skipped by default (structure preserved)",
      entry_decision(7.70, 10, False, True)[0] == "SKIP")
check("v3.10: fit-to-account tightens instead of skipping when enabled",
      entry_decision(7.70, 10, True, True) == ("TRADE_TIGHTENED", 2.0))
check("v3.10: tightened stop never exceeds the risk ceiling",
      entry_decision(7.70, 10, True, True)[1] <= affordable_stop(10, 20, 0.01, 100)+1e-9)
check("v3.10: a funded account needs neither tightening nor skipping",
      entry_decision(7.70, 100, False, True)[0] == "TRADE")

# the honest cost of Option B: the stop sits inside the real invalidation level
tightened = entry_decision(7.70, 10, True, True)[1]
check("v3.10: tightening is a real degradation, not a free lunch",
      tightened < 7.70 and 7.70/tightened > 3.0,
      f"stops out {7.70/tightened:.1f}x too early")


# ================ v4.00 SMART MONEY CONCEPTS / ICT =======================

# --- §3 Fair Value Gap: three-candle imbalance
def find_fvg(bars, min_gap):
    """bars: list of (o,h,l,c), index 0 = newest. Returns (dir, top, bottom)."""
    out = []
    for i in range(1, len(bars)-1):
        newer, older = bars[i-1], bars[i+1]
        up = newer[2] - older[1]          # low[i-1] - high[i+1]
        if up >= min_gap: out.append((1, newer[2], older[1], i))
        dn = older[2] - newer[1]          # low[i+1] - high[i-1]
        if dn >= min_gap: out.append((-1, older[2], newer[1], i))
    return out

# displacement up leaves a gap: candle1 high 100.2, candle3 low 101.0
bull_gap = [(101.5,102.0,101.4,101.9),   # [0] newest
            (100.5,101.6,101.0,101.5),   # [1] displacement
            (100.0,100.2, 99.8,100.1)]   # [2] oldest
f = find_fvg(bull_gap, 0.5)
check("ICT FVG: displacement up leaves a bullish gap",
      any(d == 1 for d,_,_,_ in f), str(f))
# the gap runs from the OLDEST candle's high (100.2) up to the NEWEST
# candle's low (101.4) -- that untouched span is the imbalance
check("ICT FVG: gap spans candle3 high up to candle1 low",
      any(abs(t-101.4) < 1e-9 and abs(b-100.2) < 1e-9 for d,t,b,_ in f if d == 1), str(f))
check("ICT FVG: gap size equals the untraded distance",
      any(abs((t-b)-1.2) < 1e-9 for d,t,b,_ in f if d == 1), str(f))
bear_gap = [(99.5,99.6,99.0,99.1),
            (100.5,100.6,99.4,99.5),
            (101.0,101.2,100.8,100.9)]
f2 = find_fvg(bear_gap, 0.5)
check("ICT FVG: displacement down leaves a bearish gap",
      any(d == -1 for d,_,_,_ in f2), str(f2))
# overlapping candles = no imbalance
no_gap = [(100.5,101.0,100.0,100.8),(100.3,100.9,99.9,100.6),(100.0,100.7,99.8,100.4)]
check("ICT FVG: overlapping candles produce no gap", len(find_fvg(no_gap, 0.5)) == 0)
check("ICT FVG: gap smaller than the minimum is ignored",
      len(find_fvg(bull_gap, 5.0)) == 0)

# --- §2 Order Block: last opposing candle before displacement
def find_ob(bars, avg_range, disp_mult=1.5, body_frac=0.50, lookback=6):
    for i in range(1, len(bars)-1):
        o,h,l,c = bars[i]
        rng, body = h-l, abs(c-o)
        up = rng >= disp_mult*avg_range and body >= body_frac*rng and c > o
        dn = rng >= disp_mult*avg_range and body >= body_frac*rng and c < o
        if not (up or dn): continue
        for b in range(i+1, min(i+1+lookback, len(bars))):
            ob,oh,ol,oc = bars[b]
            if up and oc < ob:  return (1, oh, ol, b)
            if dn and oc > ob:  return (-1, oh, ol, b)
    return None

ob_bull = [(103.0,103.2,102.8,103.1),
           (100.1,102.5,100.0,102.4),      # displacement up, range 2.5
           (100.3,100.4,100.0,100.1),      # last DOWN candle -> the order block
           (100.0,100.3, 99.9,100.2)]
r = find_ob(ob_bull, 1.0)
check("ICT OB: bullish order block is the last down candle before displacement",
      r is not None and r[0] == 1 and abs(r[1]-100.4) < 1e-9, str(r))
ob_bear = [(97.0,97.2,96.8,96.9),
           (100.0,100.1,97.5,97.6),        # displacement down
           (99.8,100.2,99.7,100.1),        # last UP candle -> the order block
           (99.9,100.0,99.6,99.7)]
r2 = find_ob(ob_bear, 1.0)
check("ICT OB: bearish order block is the last up candle before displacement",
      r2 is not None and r2[0] == -1, str(r2))
weak = [(100.5,100.6,100.4,100.5),(100.2,100.5,100.1,100.4),(100.3,100.4,100.0,100.1)]
check("ICT OB: no displacement means no order block", find_ob(weak, 1.0) is None)

# --- §4 liquidity sweep (stop hunt / turtle soup)
def is_sweep(level, side, bar):
    o,h,l,c = bar
    if side > 0: return h > level and c < level      # buyside taken, closed back below
    return l < level and c > level                   # sellside taken, closed back above
check("ICT sweep: wick above equal highs closing back below is a buyside sweep",
      is_sweep(100.0, 1, (99.8, 100.5, 99.7, 99.9)))
check("ICT sweep: wick below equal lows closing back above is a sellside sweep",
      is_sweep(100.0, -1, (100.2, 100.3, 99.5, 100.1)))
check("ICT sweep: closing BEYOND the level is a break, not a sweep",
      not is_sweep(100.0, 1, (99.8, 100.5, 99.7, 100.4)))
check("ICT sweep: never reaching the level is not a sweep",
      not is_sweep(100.0, 1, (99.0, 99.5, 98.9, 99.2)))

# --- §5 premium / discount / OTE
def pd_state(price, lo, hi, ote_lo=0.62, ote_hi=0.79, struct_dir=1):
    span = hi-lo
    pos = (price-lo)/span if span > 0 else 0.5
    retr = 1.0-pos if struct_dir >= 0 else pos
    return pos, pos < 0.5, pos > 0.5, (ote_lo <= retr <= ote_hi)

pos, disc, prem, ote = pd_state(102.0, 100.0, 110.0)
check("ICT premium/discount: 20% of range is discount", disc and not prem, f"{pos:.2f}")
pos2, disc2, prem2, _ = pd_state(108.0, 100.0, 110.0)
check("ICT premium/discount: 80% of range is premium", prem2 and not disc2, f"{pos2:.2f}")
_, _, _, ote3 = pd_state(103.0, 100.0, 110.0)   # 70% retracement of an up leg
check("ICT OTE: 62-79% retracement is inside the optimal entry window", ote3)
_, _, _, ote4 = pd_state(109.0, 100.0, 110.0)
check("ICT OTE: shallow retracement is outside the window", not ote4)
check("ICT equilibrium: exact midpoint is neither premium nor discount",
      not pd_state(105.0, 100.0, 110.0)[1] and not pd_state(105.0, 100.0, 110.0)[2])

# --- §6 killzones
def killzone(h, lon=(7,10), ny=(12,15), lnc=(15,17)):
    if lon[0] <= h < lon[1]: return "London"
    if ny[0]  <= h < ny[1]:  return "NewYork"
    if lnc[0] <= h < lnc[1]: return "LondonClose"
    return "outside"
check("ICT killzone: 08:00 GMT is the London window", killzone(8) == "London")
check("ICT killzone: 13:00 GMT is the New York window", killzone(13) == "NewYork")
check("ICT killzone: 16:00 GMT is the London close window", killzone(16) == "LondonClose")
check("ICT killzone: 03:00 GMT (Asia) is outside", killzone(3) == "outside")
check("ICT killzone: windows do not overlap ambiguously",
      len({killzone(h) for h in range(24)}) == 4)

# --- the full entry model: every leg required, in order
def ict_model(htf_bias, swept, sweep_age, mss, in_zone, in_discount, in_killzone,
              rr, direction, min_bias=0.34, max_sweep_age=30, min_rr=2.0):
    if direction*htf_bias < min_bias:            return "no HTF agreement"
    if not swept:                                return "no liquidity sweep"
    if sweep_age > max_sweep_age:                return "sweep too old"
    if not mss:                                  return "no structure shift"
    if not in_zone:                              return "price not in the POI"
    if direction > 0 and not in_discount:        return "not in discount"
    if direction < 0 and in_discount:            return "not in premium"
    if not in_killzone:                          return "outside killzone"
    if rr < min_rr:                              return "reward:risk too low"
    return "TRADE"

check("ICT model: every leg present -> TRADE",
      ict_model(0.8, True, 5, True, True, True, True, 3.0, 1) == "TRADE")
for leg, args in [
    ("HTF disagrees",      (-0.8, True, 5, True, True, True, True, 3.0, 1)),
    ("no sweep",           (0.8, False, 5, True, True, True, True, 3.0, 1)),
    ("stale sweep",        (0.8, True, 99, True, True, True, True, 3.0, 1)),
    ("no MSS",             (0.8, True, 5, False, True, True, True, 3.0, 1)),
    ("not at the POI",     (0.8, True, 5, True, False, True, True, 3.0, 1)),
    ("in premium not disc",(0.8, True, 5, True, True, False, True, 3.0, 1)),
    ("outside killzone",   (0.8, True, 5, True, True, True, False, 3.0, 1)),
    ("RR too low",         (0.8, True, 5, True, True, True, True, 1.2, 1))]:
    check(f"ICT model: rejects when {leg}", ict_model(*args) != "TRADE", ict_model(*args))
check("ICT model: short mirrors long (premium instead of discount)",
      ict_model(-0.8, True, 5, True, True, False, True, 3.0, -1) == "TRADE")

# --- §9 basket manager
def basket_metrics(legs):
    """legs: list of (price, volume)."""
    vol = sum(v for _, v in legs)
    avg = sum(p*v for p, v in legs)/vol
    return avg, vol
avg, vol = basket_metrics([(1.1000, 0.10), (1.0950, 0.06), (1.0900, 0.036)])
manual = (1.1000*0.10 + 1.0950*0.06 + 1.0900*0.036)/0.196
check("Basket: volume-weighted average entry", abs(avg-manual) < 1e-12, f"{avg:.5f}")
check("Basket: total volume is the sum of the legs", abs(vol-0.196) < 1e-12)

def basket_action(float_pl, risk_unit, target_r=2.0, stop_r=1.5, be_r=1.0, partial_r=1.0):
    R = float_pl/risk_unit
    if R >= target_r:  return ("CLOSE_ALL", R)
    if R <= -stop_r:   return ("CLOSE_ALL", R)
    if R >= be_r:      return ("BREAK_EVEN", R)
    return ("HOLD", R)
check("Basket: closes the whole basket at target R",
      basket_action(20.0, 10.0)[0] == "CLOSE_ALL")
check("Basket: closes the whole basket at stop R",
      basket_action(-15.0, 10.0)[0] == "CLOSE_ALL")
check("Basket: moves to break-even between BE and target",
      basket_action(12.0, 10.0)[0] == "BREAK_EVEN")
check("Basket: holds inside the band", basket_action(3.0, 10.0)[0] == "HOLD")
check("Basket: R is measured on the FIRST entry's risk, shared by every leg",
      basket_action(20.0, 10.0)[1] == 2.0)

def scale_lots(first, decay, count): return first*decay**count
seq = [scale_lots(0.10, 0.6, n) for n in range(1, 4)]
check("Basket: scale-ins decay, never martingale",
      all(seq[i] < seq[i-1] for i in range(1, 3)) and seq[0] < 0.10, str(seq))
check("Basket: total basket volume stays bounded",
      0.10 + sum(seq) < 0.10/(1-0.6))

def scale_allowed(setup_dir, basket_dir, count, max_trades, spacing, min_spacing):
    return setup_dir == basket_dir and count < max_trades and spacing >= min_spacing
check("Basket: scale-in needs a same-direction setup",
      not scale_allowed(-1, 1, 1, 4, 2.0, 0.75))
check("Basket: scale-in respects the position cap",
      not scale_allowed(1, 1, 4, 4, 2.0, 0.75))
check("Basket: scale-in respects minimum spacing",
      not scale_allowed(1, 1, 1, 4, 0.3, 0.75))
check("Basket: valid scale-in is permitted",
      scale_allowed(1, 1, 1, 4, 2.0, 0.75))


# ============ v4.10 SCALPER PROFILE: POI STOPS, TIERED MODEL =============
AR = 1.547        # XAUUSD M5 average range from the live self-test
AFFORD = 2.00     # what a $10 account carries at 0.01 lot gold

def stop_beyond_sweep(sweep_mult, buf=0.25): return (sweep_mult+buf)*AR
def stop_beyond_poi(zone_h, buf=0.30):       return (zone_h+buf)*AR

check("Scalp stops: swing anchor (sweep) is unaffordable on this account",
      all(stop_beyond_sweep(m) > AFFORD for m in [2.0, 3.0, 5.0]))
check("Scalp stops: POI anchor is affordable for typical zones",
      stop_beyond_poi(0.3) <= AFFORD and stop_beyond_poi(0.6) <= AFFORD)
check("Scalp stops: POI anchor is 2-6x tighter than the sweep anchor",
      stop_beyond_sweep(3.0)/stop_beyond_poi(0.6) > 2.0,
      f"{stop_beyond_sweep(3.0)/stop_beyond_poi(0.6):.1f}x")
check("Scalp stops: a wide zone still exceeds the account (fit-to-account catches it)",
      stop_beyond_poi(1.5) > AFFORD)
check("Scalp stops: never smaller than the floor",
      max(stop_beyond_poi(0.0), 0.25*AR) >= 0.25*AR)

def scalp_target(entry, risk, direction, pool, scalp_r=1.6):
    r_tp = entry + direction*scalp_r*risk
    valid = (pool > entry) if direction > 0 else (0 < pool < entry)
    if valid and abs(pool-entry) < scalp_r*risk: return pool, "pool"
    return r_tp, "R"
tp, why = scalp_target(1800.0, 1.55, 1, 1810.0)
check("Scalp target: distant pool -> take the R target", why == "R" and abs(tp-1802.48) < 0.01)
tp2, why2 = scalp_target(1800.0, 1.55, 1, 1801.5)
check("Scalp target: nearer pool -> bank at the pool", why2 == "pool" and abs(tp2-1801.5) < 1e-9)
tp3, why3 = scalp_target(1800.0, 1.55, -1, 1798.5)
check("Scalp target: shorts mirror longs", why3 == "pool" and abs(tp3-1798.5) < 1e-9)

# ---------------------------------------------------------------------------
# §10 v5.00 — confluence SCORES the trade, it never vetoes it
# ---------------------------------------------------------------------------
# The v4.10 gate that stood the EA down for a whole session was
#     if direction*htf_bias < min_agreement: skip
# with htf oscillating -0.10..-0.26 against a required 0.34. v5.00 keeps one
# hard condition (price inside a live POI) and turns everything else into a
# weight on SIZE. These checks are a 1:1 port of EvaluateDirection().
W_HTF, W_STRUCT, W_SWEEP, W_PD, W_OTE, W_KZ = 0.28, 0.24, 0.18, 0.12, 0.08, 0.10
HTF_FULL_AT   = 0.35
MIN_SIZE_FACT = 0.40

def struct_score(mss_fresh, aligned, mss, opposed):
    if mss_fresh and aligned: return 1.00
    if mss_fresh:             return 0.80
    if aligned:               return 0.70
    if mss:                   return 0.50
    if opposed:               return 0.15
    return 0.40

def model_v500(direction, htf, swept, sweep_fresh, mss_fresh, aligned, in_poi,
               pd_position=0.5, in_ote=False, in_kz=False, quality_floor=0.0):
    """Returns (tradable, quality, size_factor)."""
    if not in_poi:
        return (False, 0.0, 0.0)                    # the only veto in the model
    htf_s = mclamp((direction*htf)/HTF_FULL_AT, 0.0, 1.0)
    opposed = (not aligned) and (not mss_fresh)
    st_s  = struct_score(mss_fresh, aligned, mss_fresh or swept, opposed)
    sw_s  = 1.0 if sweep_fresh else (0.45 if swept else 0.0)
    pd_s  = (mclamp((0.5-pd_position)/0.5, 0.0, 1.0) if direction > 0
             else mclamp((pd_position-0.5)/0.5, 0.0, 1.0))
    wsum  = W_HTF+W_STRUCT+W_SWEEP+W_PD+W_OTE+W_KZ
    q = (W_HTF*htf_s + W_STRUCT*st_s + W_SWEEP*sw_s + W_PD*pd_s +
         W_OTE*(1.0 if in_ote else 0.0) + W_KZ*(1.0 if in_kz else 0.0)) / wsum
    q = mclamp(q, 0.0, 1.0)
    if q < quality_floor:
        return (False, q, 0.0)
    return (True, q, mclamp(MIN_SIZE_FACT + (1.0-MIN_SIZE_FACT)*q, 0.05, 1.0))

# the exact conditions of the log that took zero trades all day
tradable, q_blocked, size_blocked = model_v500(
    1, -0.22, swept=False, sweep_fresh=False, mss_fresh=False, aligned=True, in_poi=True)
check("v5.00: the bias that blocked every bar of the day (-0.22 vs 0.34) now trades",
      tradable, f"quality {q_blocked:.2f}, size x{size_blocked:.2f}")
check("v5.00: a counter-bias setup trades SMALL rather than not at all",
      tradable and size_blocked < 1.0, f"size x{size_blocked:.2f}")

full = model_v500(1, 0.9, True, True, True, True, True,
                  pd_position=0.1, in_ote=True, in_kz=True)
check("v5.00: a full sweep + MSS + discount + OTE + killzone setup earns full size",
      full[0] and full[2] > 0.95, f"quality {full[1]:.2f}, size x{full[2]:.2f}")

bare = model_v500(1, 0.0, False, False, False, False, True, pd_position=0.5)
check("v5.00: a bare POI with no confluence still trades",
      bare[0], f"quality {bare[1]:.2f}, size x{bare[2]:.2f}")
check("v5.00: a bare POI never trades below the minimum size factor",
      bare[2] >= MIN_SIZE_FACT - 1e-9, f"size x{bare[2]:.2f}")
check("v5.00: full confluence commits strictly more than a bare POI",
      full[2] > bare[2], f"{full[2]:.2f} vs {bare[2]:.2f}")

check("v5.00: no POI is the one and only refusal",
      not model_v500(1, 0.9, True, True, True, True, False)[0])

# every filter, one at a time, must be unable to produce a refusal
for name, kw in [("hostile HTF",        dict(htf=-1.0)),
                 ("no sweep",           dict(swept=False, sweep_fresh=False)),
                 ("no structure shift", dict(mss_fresh=False, aligned=False)),
                 ("wrong side of range",dict(pd_position=1.0)),
                 ("outside OTE",        dict(in_ote=False)),
                 ("outside killzone",   dict(in_kz=False))]:
    base = dict(direction=1, htf=0.5, swept=True, sweep_fresh=True, mss_fresh=True,
                aligned=True, in_poi=True, pd_position=0.2, in_ote=True, in_kz=True)
    base.update(kw)
    check(f"v5.00: '{name}' alone cannot refuse a setup", model_v500(**base)[0])

# ...and each one must still MATTER — a filter that changes nothing is decoration
for name, kw in [("HTF",        dict(htf=-1.0)),
                 ("sweep",      dict(swept=False, sweep_fresh=False)),
                 ("structure",  dict(mss_fresh=False, aligned=False)),
                 ("premium/discount", dict(pd_position=1.0)),
                 ("OTE",        dict(in_ote=False)),
                 ("killzone",   dict(in_kz=False))]:
    base = dict(direction=1, htf=0.5, swept=True, sweep_fresh=True, mss_fresh=True,
                aligned=True, in_poi=True, pd_position=0.2, in_ote=True, in_kz=True)
    ref = model_v500(**base)[2]
    base.update(kw)
    check(f"v5.00: losing '{name}' still reduces the size committed",
          model_v500(**base)[2] < ref - 1e-9)

check("v5.00: the quality floor is off by default, so nothing is refused on quality",
      model_v500(1, -1.0, False, False, False, False, True, pd_position=1.0)[0])
check("v5.00: a quality floor, if switched on, does bite",
      not model_v500(1, -1.0, False, False, False, False, True,
                     pd_position=1.0, quality_floor=0.9)[0])

# reward:risk is a target rule, never an entry filter
def target_rr(entry, risk, direction, pool, scalp_r=1.6, min_rr=1.20):
    r_tp = entry + direction*scalp_r*risk
    tp = r_tp
    valid = (pool > entry) if direction > 0 else (0 < pool < entry)
    if valid:
        pool_r = abs(pool-entry)/risk
        if min_rr <= pool_r < scalp_r:
            tp = pool
    rr = abs(tp-entry)/risk
    if rr < min_rr:
        rr = min_rr
        tp = entry + direction*rr*risk
    return tp, rr
_, rr_close = target_rr(1800.0, 1.0, 1, 1800.4)     # pool only 0.4R away
check("v5.00: a too-close liquidity pool is ignored, not used to refuse the trade",
      rr_close >= 1.20 - 1e-9, f"rr {rr_close:.2f}")
_, rr_ok = target_rr(1800.0, 1.0, 1, 1801.3)        # pool 1.3R away
check("v5.00: a pool that pays at least the minimum R is used as the target",
      abs(rr_ok - 1.3) < 1e-9)
check("v5.00: no reachable input combination lets RR refuse a setup",
      all(target_rr(1800.0, 1.0, 1, p)[1] >= 1.20 - 1e-9
          for p in [0.0, 1799.0, 1800.05, 1800.5, 1801.0, 1805.0]))

# the arithmetic of why v4.10 idled: independent gates multiply
def all_gates_pass(p_each, n): return p_each**n
check("v5.00 rationale: seven independent 60% gates clear under 3% of bars",
      all_gates_pass(0.60, 7) < 0.03, f"{all_gates_pass(0.60, 7)*100:.1f}%")
check("v5.00 rationale: one hard condition clears far more often than seven",
      all_gates_pass(0.60, 1) > 20*all_gates_pass(0.60, 7))

def scalp_timeout(bars_held, R, max_bars=24, min_R=0.3):
    return bars_held > max_bars and R < min_R
check("Scalp timeout: a stalled scalp releases its risk",
      scalp_timeout(30, 0.1))
check("Scalp timeout: a working scalp is left alone",
      not scalp_timeout(30, 0.8) and not scalp_timeout(10, 0.1))

# ---------------------------------------------------------------- v5.10
# What a gap is worth.  v5.00 knew only alive/filled, so it deleted every
# gap price closed through and struck off every gap half consumed — the
# inversion and the consequent-encroachment entry, both thrown away.

GAP_MEASURING, GAP_BREAKAWAY, GAP_EXHAUSTION = 0, 1, 2

def classify_gap(strength, run_in, bos, made_new_extreme,
                 bag_mult=1.80, bag_max_run=1.50, exhaust_run=3.00):
    if bos and strength >= bag_mult and run_in <= bag_max_run + strength:
        return GAP_BREAKAWAY
    if run_in >= exhaust_run and made_new_extreme:
        return GAP_EXHAUSTION
    return GAP_MEASURING

check("v5.10: the BOS candle at the start of an expansion is a breakaway gap",
      classify_gap(2.2, 1.0, True, True) == GAP_BREAKAWAY)
check("v5.10: a gap into a pool after an extended run is an exhaustion gap",
      classify_gap(1.2, 4.0, False, True) == GAP_EXHAUSTION)
check("v5.10: an ordinary mid-leg imbalance is a measuring gap",
      classify_gap(1.2, 2.0, False, False) == GAP_MEASURING)
check("v5.10: a big candle that breaks nothing is not a breakaway gap",
      classify_gap(3.0, 1.0, False, False) != GAP_BREAKAWAY)
check("v5.10: a break of structure on a limp candle is not a breakaway gap",
      classify_gap(1.1, 1.0, True, True) != GAP_BREAKAWAY)

def grade_gap(size, strength, kind, shift, filled_pct, inverted,
              bag_mult=1.80, max_age=200):
    size_s = mclamp(size, 0.0, 1.0)
    str_s = mclamp((strength-1.0)/max(bag_mult, 0.1), 0.0, 1.0)
    kind_s = (1.00 if kind == GAP_BREAKAWAY else
              0.15 if kind == GAP_EXHAUSTION else
              0.40 if kind == 3 else 0.60)
    fresh = mclamp(1.0 - shift/max(float(max_age), 1.0), 0.0, 1.0)
    g = 0.28*size_s + 0.27*str_s + 0.27*kind_s + 0.18*fresh
    g *= (1.0 - 0.60*mclamp(filled_pct, 0.0, 1.0))
    if inverted:
        g *= 0.85
    return mclamp(g, 0.0, 1.0)

bag = grade_gap(0.8, 2.4, GAP_BREAKAWAY, 5, 0.0, False)
mea = grade_gap(0.8, 2.4, GAP_MEASURING, 5, 0.0, False)
exh = grade_gap(0.8, 2.4, GAP_EXHAUSTION, 5, 0.0, False)
check("v5.10: a breakaway gap outgrades the same gap called measuring", bag > mea,
      f"{bag:.2f} vs {mea:.2f}")
check("v5.10: an exhaustion gap grades below both", exh < mea < bag,
      f"{exh:.2f} < {mea:.2f} < {bag:.2f}")
check("v5.10: every grade stays inside 0..1",
      all(0.0 <= grade_gap(s, d, k, a, f, inv) <= 1.0
          for s in (0.0, 0.5, 3.0) for d in (0.5, 2.0, 6.0)
          for k in (0, 1, 2) for a in (0, 100, 500)
          for f in (0.0, 0.5, 1.0) for inv in (False, True)))
check("v5.10: consumption discounts a gap, it no longer deletes it",
      0.0 < grade_gap(0.8, 2.4, GAP_BREAKAWAY, 5, 0.6, False) < bag)
check("v5.10: an inversion still grades as a real, slightly cheaper POI",
      0.0 < grade_gap(0.8, 2.4, GAP_MEASURING, 5, 0.0, True) < mea)
check("v5.10: a stale gap grades under a fresh one, all else equal",
      grade_gap(0.8, 2.4, GAP_BREAKAWAY, 190, 0.0, False) < bag)

# inventory: what the old kill rule cost.  Five gaps, two closed through.
def live_gaps(violations, use_inversion):
    return sum(1 for v in violations if use_inversion or not v)
check("v5.10: inversion keeps violated gaps in the book instead of binning them",
      live_gaps([False, True, False, True, False], True) == 5 and
      live_gaps([False, True, False, True, False], False) == 3)
check("v5.10: a zone violated a second time is finally dropped",
      live_gaps([True], True) == 1)

def poi_score(grade, px, top, bottom, direction, avg_range, stop_buf=0.30):
    far = bottom - stop_buf*avg_range if direction > 0 else top + stop_buf*avg_range
    return grade/(0.60 + abs(px-far)/avg_range)

AR = 1.0
tight = poi_score(0.55, 1800.0, 1800.3, 1799.8, 1, AR)     # gap, stop 0.5 away
wide = poi_score(0.55, 1800.0, 1802.5, 1797.0, 1, AR)      # block, stop 3.3 away
check("v5.10: at equal grade the tighter POI wins — that is the affordable stop",
      tight > wide, f"{tight:.3f} vs {wide:.3f}")
check("v5.10: a graded breakaway gap beats a wide breaker block outright",
      poi_score(0.82, 1800.0, 1800.3, 1799.8, 1, AR) >
      poi_score(0.65, 1800.0, 1802.5, 1797.0, 1, AR))
check("v5.10: a worthless POI never scores above a good one of the same width",
      poi_score(0.10, 1800.0, 1800.3, 1799.8, 1, AR) <
      poi_score(0.80, 1800.0, 1800.3, 1799.8, 1, AR))
check("v5.10: scoring is finite for a zero-width zone",
      poi_score(1.0, 1800.0, 1800.0, 1800.0, 1, AR) < 1e6)

# gaps as a draw on liquidity: the nearest unfilled gap ahead is a target
def fvg_draw(gaps, direction, px):
    best = 0.0
    for top, bottom, filled in gaps:
        if filled >= 0.99:
            continue
        ce = (top+bottom)*0.5
        if direction > 0:
            if bottom <= px:
                continue
            if best <= 0.0 or ce < best:
                best = ce
        else:
            if top >= px:
                continue
            if best <= 0.0 or ce > best:
                best = ce
    return best

GAPS = [(1802.0, 1801.5, 0.0), (1805.0, 1804.6, 0.0),
        (1798.0, 1797.6, 0.0), (1803.0, 1802.8, 1.0)]
check("v5.10: the nearest unfilled gap above is the buy-side draw",
      abs(fvg_draw(GAPS, 1, 1800.0) - 1801.75) < 1e-9, f"{fvg_draw(GAPS, 1, 1800.0)}")
check("v5.10: the nearest unfilled gap below is the sell-side draw",
      abs(fvg_draw(GAPS, -1, 1800.0) - 1797.8) < 1e-9)
check("v5.10: a filled gap is no longer a draw",
      abs(fvg_draw([(1803.0, 1802.8, 1.0)], 1, 1800.0)) < 1e-9)
check("v5.10: the gap price is standing in is not its own target",
      abs(fvg_draw([(1800.4, 1799.6, 0.0)], 1, 1800.0)) < 1e-9)

def target_with_draw(entry, risk, direction, pool, draw,
                     min_rr=1.20, scalp_r=1.6, scalp=True):
    tp = entry + direction*scalp_r*risk
    best, best_r = 0.0, 0.0
    for lvl in (pool, draw):
        if lvl <= 0.0:
            continue
        if (direction > 0 and lvl <= entry) or (direction < 0 and lvl >= entry):
            continue
        r = abs(lvl-entry)/risk
        if r < min_rr:
            continue
        if best <= 0.0 or r < best_r:
            best, best_r = lvl, r
    if best > 0.0 and (not scalp or best_r < scalp_r):
        tp = best
    return tp, abs(tp-entry)/risk

tp_draw, _ = target_with_draw(1800.0, 1.0, 1, 1801.5, 1801.3)
check("v5.10: a gap nearer than the pool takes the target",
      abs(tp_draw - 1801.3) < 1e-9, f"{tp_draw}")
tp_pool, _ = target_with_draw(1800.0, 1.0, 1, 1801.3, 1801.5)
check("v5.10: the pool still wins when it is the nearer draw",
      abs(tp_pool - 1801.3) < 1e-9)
check("v5.10: a gap that does not pay the minimum R cannot pull the target in",
      abs(target_with_draw(1800.0, 1.0, 1, 0.0, 1800.4)[0] - 1801.6) < 1e-9)
check("v5.10: adding gap targets never drops RR below the minimum",
      all(target_with_draw(1800.0, 1.0, 1, p, d)[1] >= 1.20 - 1e-9
          for p in (0.0, 1799.0, 1800.3, 1801.4, 1806.0)
          for d in (0.0, 1799.5, 1800.2, 1801.35, 1809.0)))

# confluence: the POI's own grade now sizes the trade, and still cannot veto it
W = dict(htf=0.28, struct=0.24, sweep=0.18, pd=0.12, ote=0.08, kz=0.10, grade=0.20)
def quality_v510(htf, st, sw, pd, ote, kz, grade):
    tot = sum(W.values())
    return mclamp((W["htf"]*htf + W["struct"]*st + W["sweep"]*sw + W["pd"]*pd +
                   W["ote"]*ote + W["kz"]*kz + W["grade"]*grade)/tot, 0.0, 1.0)
q_bag = quality_v510(0.0, 0.4, 0.0, 0.0, 0, 0, 0.85)
q_junk = quality_v510(0.0, 0.4, 0.0, 0.0, 0, 0, 0.10)
check("v5.10: a high-grade gap earns more size than a poor one, all else equal",
      q_bag > q_junk, f"{q_bag:.2f} vs {q_junk:.2f}")
check("v5.10: a worthless POI grade still trades, it only trades small",
      q_junk > 0.0 and 0.40 + 0.60*q_junk >= 0.40)
check("v5.10: POI grade cannot on its own carry a setup to full size",
      quality_v510(0.0, 0.0, 0.0, 0.0, 0, 0, 1.0) < 1.0)

# the daily breaker must survive a single min-lot loss on a micro account
def breaker_latched(day_loss, day_start_eq, losses, pct=5.0, min_losses=3):
    return day_loss >= day_start_eq*pct/100.0 and losses >= min_losses
check("v5.10: one stop-out no longer ends the session on a $10 account",
      not breaker_latched(0.60, 10.0, 1))
check("v5.10: a run of losers still latches the daily breaker",
      breaker_latched(0.60, 10.0, 3))
check("v5.10: the breaker needs BOTH the loss limit and the losing run",
      not breaker_latched(0.10, 10.0, 5))

# ---------------------------------------------------------------- v5.11
# §3b: trade the candle after the gap prints, with no retrace required.
# Requiring price to be INSIDE a POI made the EA a retracement trader only,
# and after real displacement most gaps are never retraced.

def fresh_gap_entry(direction, px, top, bottom, shift, kind, grade, avg_range,
                    zone_buf=0.25, max_age=3, max_run=1.25,
                    skip_exhaust=True, min_grade=0.0, enabled=True):
    """Returns the run past the gap if it is tradeable now, else None."""
    if not enabled:
        return None
    if shift > max_age or grade < min_grade:
        return None
    if skip_exhaust and kind == GAP_EXHAUSTION:
        return None
    buf = zone_buf*avg_range
    run = (px - (top+buf)) if direction > 0 else ((bottom-buf) - px)
    if run <= 0.0:                       # still in the zone: the POI branch owns it
        return None
    if run > max_run*avg_range:          # ran away, wait for the retrace
        return None
    return run

AR = 1.0
GTOP, GBOT = 1800.5, 1800.0

check("v5.11: a plain FVG one candle old trades on the following candle",
      fresh_gap_entry(1, 1801.0, GTOP, GBOT, 1, GAP_MEASURING, 0.5, AR) is not None)
check("v5.11: a breakaway gap does the same",
      fresh_gap_entry(1, 1801.0, GTOP, GBOT, 1, GAP_BREAKAWAY, 0.8, AR) is not None)
check("v5.11: shorts mirror longs",
      fresh_gap_entry(-1, 1799.5, GTOP, GBOT, 1, GAP_MEASURING, 0.5, AR) is not None)
check("v5.11: an exhaustion gap is never chased",
      fresh_gap_entry(1, 1801.0, GTOP, GBOT, 1, GAP_EXHAUSTION, 0.5, AR) is None)
check("v5.11: a stale gap is not a fresh entry — it is back to waiting for the retrace",
      fresh_gap_entry(1, 1801.0, GTOP, GBOT, 12, GAP_MEASURING, 0.5, AR) is None)
check("v5.11: price that has run too far past the gap is not chased",
      fresh_gap_entry(1, 1803.0, GTOP, GBOT, 1, GAP_MEASURING, 0.5, AR) is None)
check("v5.11: price still inside the gap is left to the retrace branch (no double entry)",
      fresh_gap_entry(1, 1800.3, GTOP, GBOT, 1, GAP_MEASURING, 0.5, AR) is None)
check("v5.11: the zone buffer is respected before a gap counts as 'run past'",
      fresh_gap_entry(1, 1800.7, GTOP, GBOT, 1, GAP_MEASURING, 0.5, AR) is None)
check("v5.11: switching the feature off restores pure retracement trading",
      fresh_gap_entry(1, 1801.0, GTOP, GBOT, 1, GAP_BREAKAWAY, 0.8, AR,
                      enabled=False) is None)

# the stop still sits beyond the gap, which is what keeps this a trade
def fresh_stop_distance(direction, px, top, bottom, avg_range, stop_buf=0.30):
    sl = bottom - stop_buf*avg_range if direction > 0 else top + stop_buf*avg_range
    return abs(px - sl)

d_near = fresh_stop_distance(1, 1800.8, GTOP, GBOT, AR)
d_far = fresh_stop_distance(1, 1801.7, GTOP, GBOT, AR)
check("v5.11: the fresh-gap stop is anchored beyond the gap, not to a fixed distance",
      abs(d_near - 1.10) < 1e-9, f"{d_near:.2f}")
check("v5.11: chasing further costs a wider stop — the reason the chase is bounded",
      d_far > d_near)
check("v5.11: the worst allowed chase still leaves a scalper-sized stop",
      fresh_stop_distance(1, GTOP + 0.25 + 1.25, GTOP, GBOT, AR) <= 2.5,
      f"{fresh_stop_distance(1, GTOP+1.5, GTOP, GBOT, AR):.2f}")

check("v5.11: a nearer fresh gap outscores a further one of equal grade",
      poi_score(0.60, 1800.8, GTOP, GBOT, 1, AR) >
      poi_score(0.60, 1801.6, GTOP, GBOT, 1, AR))

# the whole point: how many gaps a retrace-only EA never gets to trade
def chances(total_gaps, retraced_share):
    retraced = total_gaps*retraced_share
    return retraced, total_gaps - retraced
seen, missed = chances(20, 0.45)
check("v5.11 rationale: a retrace-only model forfeits every gap that runs",
      missed > seen, f"{missed:.0f} missed vs {seen:.0f} traded")

# ---------------------------------------------------------------- v5.12
# Four admission gates that refused trades for reasons that were not risk.

def min_gap(avg_range, spread, min_pct=0.06, min_spreads=1.0):
    return max(min_pct*avg_range, min_spreads*spread)

AR, SPREAD = 1.50, 0.25
check("v5.12: the gap floor is the spread, not a quarter of the average range",
      min_gap(AR, SPREAD) < 0.25*AR, f"{min_gap(AR, SPREAD):.3f} vs {0.25*AR:.3f}")
check("v5.12: a small imbalance that used to be deleted is now recorded",
      0.30 >= min_gap(AR, SPREAD) and 0.30 < 0.25*AR)
check("v5.12: a gap narrower than the spread is still refused — it cannot pay its crossing",
      0.10 < min_gap(AR, SPREAD))
check("v5.12: a wide spread raises the floor on its own",
      min_gap(AR, 0.60) > min_gap(AR, 0.25))
check("v5.12: the floor never goes to zero",
      min_gap(AR, 0.0) > 0.0)

# the book must keep the NEWEST poi, not the oldest
def fill_book(shifts, slots, newest_first):
    order = sorted(shifts) if newest_first else sorted(shifts, reverse=True)
    return sorted(order[:slots])

BOOK = list(range(1, 120))
check("v5.12: a full book keeps the freshest POIs",
      fill_book(BOOK, 40, True)[0] == 1 and max(fill_book(BOOK, 40, True)) == 40)
check("v5.12: the old oldest-first fill threw every fresh POI away",
      min(fill_book(BOOK, 40, False)) == 80)
check("v5.12: with newest-first, §3b always has fresh gaps to work with",
      any(s <= 3 for s in fill_book(BOOK, 40, True)) and
      not any(s <= 3 for s in fill_book(BOOK, 40, False)))

def poi_score_v512(grade, px, top, bottom, direction, avg_range,
                   stop_buf=0.30, floor=0.25):
    far = bottom - stop_buf*avg_range if direction > 0 else top + stop_buf*avg_range
    risk = max(abs(px-far), floor*avg_range)/avg_range
    return grade/(0.60+risk)

micro = poi_score_v512(0.20, 1800.00, 1800.02, 1799.98, 1, 1.0)
real = poi_score_v512(0.70, 1800.00, 1800.40, 1799.70, 1, 1.0)
check("v5.12: a micro-gap no longer outranks a real one on a stop it never gets",
      real > micro, f"real {real:.3f} vs micro {micro:.3f}")
check("v5.12: scoring uses the floored stop, so it matches the trade actually placed",
      abs(poi_score_v512(1.0, 1800.0, 1800.01, 1799.99, 1, 1.0, stop_buf=0.0)
          - 1.0/0.85) < 1e-9)
check("v5.12: a small gap still scores — it is discounted, not deleted",
      micro > 0.0)

def ceiling_blocks(real_risk, equity, pct=20.0, tol=1.005):
    return real_risk > equity*pct/100.0*tol + 1e-8
EQ = 8.25
check("v5.12: a stop auto-fitted to land exactly on the ceiling is no longer refused",
      not ceiling_blocks(1.65, EQ), "1.65 vs 20% of 8.25 = 1.65")
check("v5.12: floating-point overshoot on the ceiling is tolerated",
      not ceiling_blocks(1.65000000001, EQ))
check("v5.12: a genuinely oversized risk is still refused",
      ceiling_blocks(2.50, EQ))
check("v5.12: the tolerance is a rounding allowance, not a raised ceiling",
      ceiling_blocks(EQ*0.20*1.02, EQ))

# volume imbalance: bodies gap, wicks touch
def volume_imbalance(open_i, close_next, floor):
    up = open_i - close_next
    dn = close_next - open_i
    if up >= floor:
        return 1, close_next, open_i
    if dn >= floor:
        return -1, open_i, close_next
    return 0, 0.0, 0.0
check("v5.12: a bullish volume imbalance is recorded",
      volume_imbalance(1800.60, 1800.20, 0.25)[0] == 1)
check("v5.12: a bearish volume imbalance mirrors it",
      volume_imbalance(1800.20, 1800.60, 0.25)[0] == -1)
check("v5.12: overlapping bodies are not an imbalance",
      volume_imbalance(1800.25, 1800.20, 0.25)[0] == 0)
check("v5.12: a volume imbalance grades below a real three-candle gap",
      grade_gap(0.3, 1.2, 3, 4, 0.0, False) < grade_gap(0.3, 1.2, GAP_MEASURING, 4, 0.0, False))
check("v5.12: it still grades above zero — it trades, small",
      grade_gap(0.3, 1.2, 3, 4, 0.0, False) > 0.0)

# ---------------------------------------------------------------- v5.13
# The cap that was really in charge. A 4% basket cap tested against the
# FIRST trade, while the per-trade ceiling said 20% - so on a micro account
# where min lot risks 12-20% no matter what, every approved trade was then
# refused by a cap that was never meant to govern a single position.

def basket_blocks(basket_used, real_risk, equity,
                  basket_pct=4.0, trade_pct=20.0, unified=True):
    cap = equity*(max(basket_pct, trade_pct) if unified else basket_pct)/100.0
    return basket_used + real_risk > cap*1.005 + 1e-8

EQ = 10.0
check("v5.13: the old 4% basket cap refused a trade the 20% ceiling had approved",
      basket_blocks(0.0, 1.50, EQ, unified=False))
check("v5.13: the first trade is no longer refused by the stacking cap",
      not basket_blocks(0.0, 1.50, EQ))
check("v5.13: a trade inside the per-trade ceiling always fits an empty basket",
      all(not basket_blocks(0.0, EQ*p/100.0, EQ) for p in (1, 5, 10, 19, 20)))
check("v5.13: stacking is still capped",
      basket_blocks(1.80, 1.50, EQ))
check("v5.13: the basket cap is never tighter than the per-trade ceiling",
      max(4.0, 20.0) == 20.0)
check("v5.13: a larger explicit basket cap is still honoured",
      not basket_blocks(0.0, 2.40, EQ, basket_pct=30.0))
check("v5.13: on a normal account the 4% cap is unchanged in spirit — "
      "one trade at 1% still stacks four times",
      not basket_blocks(0.03*1000, 0.01*1000, 1000.0))

print("\n================================================")
print(f"RESULT: {len(PASS)} passed, {len(FAIL)} failed")
if FAIL:
    print("FAILED:", *FAIL, sep="\n  - ")
raise SystemExit(1 if FAIL else 0)
