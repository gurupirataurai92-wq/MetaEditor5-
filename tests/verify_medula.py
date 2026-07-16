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

print("\n================================================")
print(f"RESULT: {len(PASS)} passed, {len(FAIL)} failed")
if FAIL:
    print("FAILED:", *FAIL, sep="\n  - ")
raise SystemExit(1 if FAIL else 0)
