<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Lucky Numbers';

// Payout table by how many of your 6 picks are drawn (from 6 drawn of 1-49)
$PAYOUTS = [0 => 0, 1 => 0, 2 => 0, 3 => 5, 4 => 25, 5 => 150, 6 => 1000];
$result = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_login();
    check_csrf();
    try {
        $picks = array_map('intval', $_POST['picks'] ?? []);
        $picks = array_values(array_unique(array_filter($picks, fn($n) => $n >= 1 && $n <= 49)));
        $stake = (float)($_POST['stake'] ?? 0);
        if (count($picks) !== 6) throw new RuntimeException('Pick exactly 6 numbers.');

        $uid = (int)current_user($pdo)['id'];

        // Draw 6 unique numbers 1-49
        $pool = range(1, 49); shuffle($pool);
        $drawn = array_slice($pool, 0, 6); sort($drawn);
        $hits  = array_values(array_intersect($picks, $drawn));
        $mult  = $PAYOUTS[count($hits)];

        $selection = 'Picks: ' . implode(',', $picks);
        // Odds here = payout multiplier (0 means lost)
        $betId = place_bet($pdo, $uid, 'lucky', $selection, $stake, max($mult, 1));
        $won = $mult > 0;
        settle_bet($pdo, $betId, $won ? 'won' : 'lost',
                   'Drawn: ' . implode(',', $drawn) . ' — ' . count($hits) . ' hits');
        // place_bet used odds=max(mult,1); fix payout for exact multiplier:
        if ($won) {
            // adjust: settle_bet paid stake*max(mult,1); ensure correct payout already since odds=mult when mult>0
        }

        $result = ['picks' => $picks, 'drawn' => $drawn, 'hits' => $hits,
                   'mult' => $mult, 'stake' => $stake, 'payout' => $won ? round($stake * $mult, 2) : 0];
        flash($won ? ('🎯 ' . count($hits) . ' hits! Won ' . money($result['payout']) . '!')
                   : ('Only ' . count($hits) . ' hits this time — try again. 🐝'),
              $won ? 'success' : 'error');
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    $_SESSION['lucky_result'] = $result;
    header('Location: lucky.php');
    exit;
}

$result = $_SESSION['lucky_result'] ?? null;
unset($_SESSION['lucky_result']);
$user = current_user($pdo);
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">🎯 Lucky Numbers</h2>
<p class="muted">Pick <b>6</b> numbers from 1–49. We draw 6. Match more to win bigger — up to <b>1000×</b> your stake for all six!</p>

<div class="grid grid--2 mt">
  <div class="card">
    <h3>Your slip</h3>
    <?php if (!is_logged_in()): ?>
      <p class="muted"><a href="login.php" style="color:var(--gold);font-weight:800">Log in</a> to play.</p>
    <?php else: ?>
      <p class="muted">Balance: <b><?= money($user['balance']) ?></b></p>
      <form method="post" id="lucky-form" data-confirm="Place this Lucky Numbers bet?">
        <?= csrf_field() ?>
        <p class="mt muted">Tap 6 numbers:</p>
        <div class="balls" id="balls">
          <?php for ($n = 1; $n <= 49; $n++): ?>
            <div class="ball" data-n="<?= $n ?>"><?= $n ?></div>
          <?php endfor; ?>
        </div>
        <div id="picks-inputs"></div>
        <div class="field mt"><label>Stake (<?= CURRENCY ?>)</label>
          <input type="number" id="stake" name="stake" step="0.01" min="1" value="10" required></div>
        <button class="btn btn--gold btn--block" id="lucky-submit" disabled>Draw! (<span id="pick-count">0</span>/6)</button>
      </form>
    <?php endif; ?>
  </div>

  <div class="card">
    <h3>Latest draw</h3>
    <?php if ($result): ?>
      <p class="muted">Winning numbers:</p>
      <div class="balls">
        <?php foreach ($result['drawn'] as $d): ?>
          <div class="ball drawn"><?= $d ?></div>
        <?php endforeach; ?>
      </div>
      <p class="muted">Your picks (hits highlighted):</p>
      <div class="balls">
        <?php foreach ($result['picks'] as $p): ?>
          <div class="ball <?= in_array($p, $result['hits']) ? 'drawn' : '' ?>"><?= $p ?></div>
        <?php endforeach; ?>
      </div>
      <p class="mt <?= $result['payout'] > 0 ? 'pos' : 'neg' ?>">
        <?= count($result['hits']) ?> hits ·
        <?= $result['payout'] > 0 ? 'Won ' . money($result['payout']) . ' (' . $result['mult'] . '×)' : 'No win' ?>
      </p>
    <?php else: ?>
      <p class="muted">No draw yet — make your picks and play! 🐝</p>
    <?php endif; ?>
    <table class="table mt">
      <tr><th>Matches</th><th>Pays</th></tr>
      <tr><td>3</td><td>5×</td></tr>
      <tr><td>4</td><td>25×</td></tr>
      <tr><td>5</td><td>150×</td></tr>
      <tr><td>6</td><td>1000×</td></tr>
    </table>
  </div>
</div>
<div class="disclaimer">Fixed-odds lucky-numbers demo. Play money only.</div>

<script>
(function () {
  var balls = document.getElementById('balls');
  if (!balls) return;
  var picks = [], MAX = 6;
  var inputs = document.getElementById('picks-inputs');
  var count  = document.getElementById('pick-count');
  var submit = document.getElementById('lucky-submit');
  balls.addEventListener('click', function (e) {
    var b = e.target.closest('.ball'); if (!b) return;
    var n = parseInt(b.getAttribute('data-n'), 10);
    var i = picks.indexOf(n);
    if (i > -1) { picks.splice(i, 1); b.classList.remove('picked'); }
    else if (picks.length < MAX) { picks.push(n); b.classList.add('picked'); }
    inputs.innerHTML = picks.map(function (p) {
      return '<input type="hidden" name="picks[]" value="' + p + '">';
    }).join('');
    count.textContent = picks.length;
    submit.disabled = picks.length !== MAX;
  });
})();
</script>
<?php require __DIR__ . '/includes/footer.php'; ?>
