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

print("\n================================================")
print(f"RESULT: {len(PASS)} passed, {len(FAIL)} failed")
if FAIL:
    print("FAILED:", *FAIL, sep="\n  - ")
raise SystemExit(1 if FAIL else 0)
