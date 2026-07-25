<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Aviator';
$user = current_user($pdo);
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">✈️ Aviator — live</h2>
<p class="muted">Place your stake, the plane takes off and the multiplier climbs in real time. Hit <b>Cash Out</b> before it flies away to lock in <b>stake × multiplier</b>. Wait too long and you lose the stake.</p>

<div class="grid grid--2 mt">
  <div class="card">
    <div class="aviator" id="aviator">
      <div class="aviator__status" id="av-status">Ready for take-off</div>
      <div class="aviator__mult" id="av-mult">1.00×</div>
      <div class="aviator__plane" id="av-plane">✈️</div>
    </div>
    <p class="center mt muted" id="av-fair" style="font-size:.8rem;word-break:break-all"></p>
  </div>

  <div class="card">
    <h3>Controls</h3>
    <?php if (!is_logged_in()): ?>
      <p class="muted"><a href="login.php" style="color:var(--gold);font-weight:800">Log in</a> to play.</p>
    <?php else: ?>
      <p class="muted">Balance: <b id="av-balance"><?= money($user['balance']) ?></b></p>
      <div class="field mt"><label>Stake (<?= CURRENCY ?>)</label>
        <input type="number" id="stake" min="1" step="0.01" value="10"></div>
      <div class="pill-row">
        <span class="pill" data-stake="5"  data-target="#stake" style="cursor:pointer">5</span>
        <span class="pill" data-stake="10" data-target="#stake" style="cursor:pointer">10</span>
        <span class="pill" data-stake="25" data-target="#stake" style="cursor:pointer">25</span>
        <span class="pill" data-stake="50" data-target="#stake" style="cursor:pointer">50</span>
      </div>
      <button class="btn btn--gold btn--block mt" id="av-play">🚀 Take off</button>
      <button class="btn btn--green btn--block mt" id="av-cashout" style="display:none">💰 Cash out <span id="av-cashout-mult">1.00×</span></button>
      <p class="muted mt" id="av-msg" style="font-size:.85rem"></p>
      <p class="muted mt" style="font-size:.8rem">Provably fair: we show the SHA-256 of the round seed before take-off and reveal the seed after — verify that it produces the crash point.</p>
    <?php endif; ?>
  </div>
</div>
<div class="disclaimer">Live server-authoritative demo: the crash point is committed before the round and the server decides the outcome. Play money only.</div>

<script>
window.HIVE_CSRF = <?= json_encode(csrf_token()) ?>;
</script>
<script src="assets/js/aviator.js"></script>
<?php require __DIR__ . '/includes/footer.php'; ?>
