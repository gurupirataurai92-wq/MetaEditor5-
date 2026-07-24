<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Jackpot';

$jackpot = $pdo->query('SELECT * FROM jackpots WHERE status = "open" ORDER BY draw_at LIMIT 1')->fetch();
// Use the 6 open events as the jackpot slate
$slate = $pdo->query('SELECT * FROM events WHERE status = "open" ORDER BY starts_at LIMIT 8')->fetchAll();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_login();
    check_csrf();
    try {
        if (!$jackpot) throw new RuntimeException('No open jackpot right now.');
        $preds = $_POST['pred'] ?? [];
        if (count($preds) < count($slate)) throw new RuntimeException('Predict every match on the slate.');

        $uid   = (int)current_user($pdo)['id'];
        $price = (float)$jackpot['ticket_price'];

        // Encode the ticket selections
        $parts = [];
        foreach ($slate as $ev) {
            $p = $preds[$ev['id']] ?? '?';
            $parts[] = $ev['home'] . ' v ' . $ev['away'] . '=' . strtoupper($p[0] ?? '?');
        }
        $selection = $jackpot['title'] . ' ticket';
        // Ticket is a pending bet; odds are notional (pool-based), settled by admin later.
        $betId = place_bet($pdo, $uid, 'jackpot', $selection, $price, 1.0, (int)$jackpot['id']);

        // Grow the pool by the ticket price
        $pdo->prepare('UPDATE jackpots SET pool = pool + ? WHERE id = ?')
            ->execute([$price, $jackpot['id']]);

        flash('🏆 Jackpot ticket bought for ' . money($price) . '! Good luck. Draw ' . date('D d M', strtotime($jackpot['draw_at'])) . '.', 'success');
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    header('Location: jackpot.php');
    exit;
}

$tickets = 0;
if ($jackpot) {
    $t = $pdo->prepare('SELECT COUNT(*) FROM bets WHERE game = "jackpot" AND event_id = ?');
    $t->execute([$jackpot['id']]);
    $tickets = (int)$t->fetchColumn();
}
$user = current_user($pdo);
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">🏆 Weekend Mega Jackpot</h2>

<?php if (!$jackpot): ?>
  <div class="card"><p class="muted center">No jackpot is open right now — check back soon. 🐝</p></div>
<?php else: ?>
<div class="card center" style="background:radial-gradient(500px 220px at 50% 0%,rgba(255,176,0,.20),transparent),linear-gradient(180deg,var(--panel),var(--bg-2))">
  <p class="muted"><?= e($jackpot['title']) ?></p>
  <div style="font-size:3rem;font-weight:900;color:var(--gold);text-shadow:var(--glow)"><?= money($jackpot['pool']) ?></div>
  <div class="pill-row" style="justify-content:center">
    <span class="pill">🎟 <?= money($jackpot['ticket_price']) ?> per ticket</span>
    <span class="pill"><?= count($slate) ?> matches</span>
    <span class="pill"><?= $tickets ?> tickets in</span>
    <span class="pill">Draws <?= date('D d M · H:i', strtotime($jackpot['draw_at'])) ?></span>
  </div>
</div>

<div class="card mt">
  <h3>Predict the slate</h3>
  <p class="muted">Call every match (Home / Draw / Away). Get them all right to share the pool.</p>
  <?php if (!is_logged_in()): ?>
    <p class="muted mt"><a href="login.php" style="color:var(--gold);font-weight:800">Log in</a> to buy a ticket.</p>
  <?php else: ?>
  <form method="post" class="mt" data-confirm="Buy this jackpot ticket?">
    <?= csrf_field() ?>
    <?php foreach ($slate as $i => $ev): ?>
      <div class="event">
        <div class="event__teams">
          <div class="pill" style="margin-bottom:6px">Match <?= $i + 1 ?> · <?= e($ev['league']) ?></div>
          <b><?= e($ev['home']) ?> <span class="muted">vs</span> <?= e($ev['away']) ?></b>
        </div>
        <div style="display:flex;gap:8px">
          <label class="odds-btn"><input type="radio" name="pred[<?= $ev['id'] ?>]" value="home" required> 1</label>
          <label class="odds-btn"><input type="radio" name="pred[<?= $ev['id'] ?>]" value="draw"> X</label>
          <label class="odds-btn"><input type="radio" name="pred[<?= $ev['id'] ?>]" value="away"> 2</label>
        </div>
      </div>
    <?php endforeach; ?>
    <button class="btn btn--gold btn--block mt">🎟 Buy ticket for <?= money($jackpot['ticket_price']) ?></button>
  </form>
  <?php endif; ?>
</div>
<?php endif; ?>
<div class="disclaimer">Pool-based jackpot demo: ticket sales grow the pool; the admin settles the draw. Play money only.</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
