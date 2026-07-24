<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Gold Market';

const GOLD_ODDS = 1.90;   // binary payout (≈5% house margin on a 50/50)
$result = null;

// A demo "live" gold price that drifts each minute (seeded by the hour+minute).
function gold_price(): float {
    $base = 2400.0;
    $t = (int)(time() / 60);
    $wave = sin($t / 7) * 18 + cos($t / 3) * 9;
    return round($base + $wave, 2);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_login();
    check_csrf();
    try {
        $dir   = $_POST['dir'] ?? '';        // up | down
        $stake = (float)($_POST['stake'] ?? 0);
        if (!in_array($dir, ['up', 'down'], true)) throw new RuntimeException('Choose UP or DOWN.');

        $uid   = (int)current_user($pdo)['id'];
        $open  = gold_price();
        // Simulate the settlement tick (random walk around a tiny drift)
        $move  = (mt_rand(-100, 100) / 100.0) * 6.5;   // ± up to 6.5
        $close = round($open + $move, 2);
        $wentUp = $close >= $open;
        $won    = ($dir === 'up' && $wentUp) || ($dir === 'down' && !$wentUp);

        $selection = 'XAUUSD ' . strtoupper($dir) . ' from ' . number_format($open, 2);
        $betId = place_bet($pdo, $uid, 'financial', $selection, $stake, GOLD_ODDS);
        settle_bet($pdo, $betId, $won ? 'won' : 'lost',
                   'Open ' . number_format($open, 2) . ' → Close ' . number_format($close, 2));

        $result = ['dir' => $dir, 'open' => $open, 'close' => $close,
                   'up' => $wentUp, 'won' => $won, 'stake' => $stake,
                   'payout' => $won ? round($stake * GOLD_ODDS, 2) : 0];
        flash($won ? ('📈 Right call! Gold went ' . ($wentUp ? 'UP' : 'DOWN') . ' — won ' . money($result['payout']) . '!')
                   : ('📉 Gold went ' . ($wentUp ? 'UP' : 'DOWN') . '. Better luck next tick.'),
              $won ? 'success' : 'error');
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    $_SESSION['fin_result'] = $result;
    header('Location: financial.php');
    exit;
}

$result = $_SESSION['fin_result'] ?? null;
unset($_SESSION['fin_result']);
$price = gold_price();
$user  = current_user($pdo);
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">📈 Gold Market Bets</h2>
<p class="muted">Our signature game — bet whether gold (XAUUSD) ticks <b>UP</b> or <b>DOWN</b> next. In production this settles from the same live MT5 feed that powers the GoldPortfolio trading bot. Win pays <b><?= GOLD_ODDS ?>×</b>.</p>

<div class="grid grid--2 mt">
  <div class="card center" style="background:radial-gradient(400px 200px at 50% 0%,rgba(255,176,0,.16),transparent),linear-gradient(180deg,var(--panel),var(--bg-2))">
    <p class="muted">XAUUSD · live demo price</p>
    <div style="font-size:3.2rem;font-weight:900;color:var(--gold);text-shadow:var(--glow)">$<?= number_format($price, 2) ?></div>
    <div class="pill-row" style="justify-content:center">
      <span class="pill">Gold spot</span><span class="pill">Binary · <?= GOLD_ODDS ?>×</span><span class="pill">Beat the Bot 🤖</span>
    </div>
    <?php if ($result): ?>
      <div class="card mt" style="background:var(--panel-2)">
        <p>Open <b>$<?= number_format($result['open'],2) ?></b> → Close <b>$<?= number_format($result['close'],2) ?></b></p>
        <p class="<?= $result['up'] ? 'pos' : 'neg' ?>" style="font-size:1.4rem">
          Gold went <?= $result['up'] ? 'UP ▲' : 'DOWN ▼' ?>
        </p>
        <p class="<?= $result['won'] ? 'pos' : 'neg' ?>">
          You bet <?= strtoupper($result['dir']) ?> —
          <?= $result['won'] ? 'won ' . money($result['payout']) : 'lost ' . money($result['stake']) ?>
        </p>
      </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <h3>Your call</h3>
    <?php if (!is_logged_in()): ?>
      <p class="muted"><a href="login.php" style="color:var(--gold);font-weight:800">Log in</a> to play.</p>
    <?php else: ?>
      <p class="muted">Balance: <b><?= money($user['balance']) ?></b></p>
      <form method="post" class="mt">
        <?= csrf_field() ?>
        <div class="field"><label>Stake (<?= CURRENCY ?>)</label>
          <input type="number" name="stake" step="0.01" min="1" value="10" required></div>
        <div class="grid grid--2" style="gap:12px">
          <button class="btn btn--green btn--block" name="dir" value="up">▲ UP</button>
          <button class="btn btn--red btn--block" name="dir" value="down">▼ DOWN</button>
        </div>
      </form>
      <p class="muted mt" style="font-size:.82rem">Predict the next tick. Win pays <?= GOLD_ODDS ?>× your stake; the ~5% edge is the hive's margin.</p>
    <?php endif; ?>
  </div>
</div>
<div class="disclaimer">Demo price simulation. In a licensed build this settles deterministically from recorded market ticks — no disputes. Play money only.</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
