<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Aviator';

$round = null; // result of the just-played round (for animation)

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_login();
    check_csrf();
    try {
        $stake  = (float)($_POST['stake'] ?? 0);
        $target = (float)($_POST['cashout'] ?? 0);   // auto cash-out multiplier
        if ($target < 1.01) throw new RuntimeException('Auto cash-out must be at least 1.01×.');

        $uid = (int)current_user($pdo)['id'];

        // Provably-fair crash point from a per-round seed
        $seed  = bin2hex(random_bytes(8)) . '|' . $uid . '|' . microtime(true);
        $crash = crash_point($seed);
        $won   = $crash >= $target;

        $selection = 'Aviator — auto cash-out ' . number_format($target, 2) . '×';
        $betId = place_bet($pdo, $uid, 'aviator', $selection, $stake, $target);
        settle_bet($pdo, $betId, $won ? 'won' : 'lost',
                   'Crashed at ' . number_format($crash, 2) . '×');

        $round = [
            'crash'  => $crash,
            'target' => $target,
            'won'    => $won,
            'stake'  => $stake,
            'payout' => $won ? round($stake * $target, 2) : 0,
        ];
        flash($won
            ? 'Cashed out at ' . number_format($target, 2) . '× — won ' . money($round['payout']) . '! 🍯'
            : 'Busted at ' . number_format($crash, 2) . '× before your ' . number_format($target, 2) . '×. 💥',
            $won ? 'success' : 'error');
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    $_SESSION['aviator_round'] = $round;
    header('Location: aviator.php');
    exit;
}

$round = $_SESSION['aviator_round'] ?? null;
unset($_SESSION['aviator_round']);
$user = current_user($pdo);

require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">✈️ Aviator</h2>
<p class="muted">Set your stake and an auto cash-out multiplier. The plane climbs — if it reaches your target before it flies away, you win <b>stake × multiplier</b>.</p>

<div class="grid grid--2 mt">
  <div class="card">
    <div class="aviator" id="aviator"
         data-crash="<?= e($round['crash'] ?? '') ?>"
         data-target="<?= e($round['target'] ?? '') ?>"
         data-won="<?= isset($round['won']) ? ($round['won'] ? '1' : '0') : '' ?>">
      <div class="aviator__status" id="av-status"><?= $round ? 'Round complete' : 'Ready for take-off' ?></div>
      <div class="aviator__mult <?= (isset($round['won']) && !$round['won']) ? 'busted' : '' ?>" id="av-mult">
        <?= $round ? number_format($round['crash'], 2) . '×' : '1.00×' ?>
      </div>
      <div class="aviator__plane" id="av-plane">✈️</div>
    </div>
    <?php if ($round): ?>
      <p class="mt center <?= $round['won'] ? 'pos' : 'neg' ?>">
        <?= $round['won']
            ? '✅ Won ' . money($round['payout']) . ' (target ' . number_format($round['target'],2) . '×)'
            : '💥 Busted at ' . number_format($round['crash'],2) . '× — lost ' . money($round['stake']) ?>
      </p>
    <?php endif; ?>
  </div>

  <div class="card">
    <h3>Place your flight</h3>
    <?php if (!is_logged_in()): ?>
      <p class="muted"><a href="login.php" style="color:var(--gold);font-weight:800">Log in</a> to play.</p>
    <?php else: ?>
      <p class="muted">Balance: <b><?= money($user['balance']) ?></b></p>
      <form method="post" class="mt">
        <?= csrf_field() ?>
        <div class="field"><label>Stake (<?= CURRENCY ?>)</label>
          <input type="number" id="stake" name="stake" step="0.01" min="1" value="10" required></div>
        <div class="pill-row">
          <span class="pill" data-stake="5"  data-target="#stake" style="cursor:pointer">5</span>
          <span class="pill" data-stake="10" data-target="#stake" style="cursor:pointer">10</span>
          <span class="pill" data-stake="25" data-target="#stake" style="cursor:pointer">25</span>
          <span class="pill" data-stake="50" data-target="#stake" style="cursor:pointer">50</span>
        </div>
        <div class="field"><label>Auto cash-out (×)</label>
          <input type="number" name="cashout" step="0.01" min="1.01" value="2.00" required></div>
        <button class="btn btn--gold btn--block">🚀 Take off</button>
      </form>
      <p class="muted mt" style="font-size:.82rem">Higher targets pay more but bust more often. ~3% of rounds crash instantly at 1.00× (the house edge).</p>
    <?php endif; ?>
  </div>
</div>
<div class="disclaimer">Provably-fair demo: each crash point is derived from a random per-round seed. Play money only.</div>

<script>
// Animate the plane climbing to the round's crash multiplier
(function () {
  var box = document.getElementById('aviator');
  if (!box) return;
  var crash = parseFloat(box.getAttribute('data-crash'));
  var won   = box.getAttribute('data-won');
  if (!crash) return;
  var multEl = document.getElementById('av-mult');
  var plane  = document.getElementById('av-plane');
  var status = document.getElementById('av-status');
  var cur = 1.0, t0 = performance.now(), dur = Math.min(600 + crash * 350, 4000);
  multEl.classList.remove('busted');
  status.textContent = 'Flying…';
  function frame(now) {
    var p = Math.min((now - t0) / dur, 1);
    cur = 1 + (crash - 1) * p;
    multEl.textContent = cur.toFixed(2) + '×';
    plane.style.left = (8 + p * 74) + '%';
    plane.style.bottom = (12 + p * 60) + '%';
    if (p < 1) { requestAnimationFrame(frame); }
    else {
      status.textContent = 'Round complete';
      if (won === '0') { multEl.classList.add('busted'); plane.textContent = '💥'; }
    }
  }
  requestAnimationFrame(frame);
})();
</script>
<?php require __DIR__ . '/includes/footer.php'; ?>
