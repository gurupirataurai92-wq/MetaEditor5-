<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Sports';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_login();
    check_csrf();
    try {
        $eventId = (int)($_POST['event_id'] ?? 0);
        $pick    = $_POST['pick'] ?? '';               // home | draw | away
        $stake   = (float)($_POST['stake'] ?? 0);

        $stmt = $pdo->prepare('SELECT * FROM events WHERE id = ? AND status = "open"');
        $stmt->execute([$eventId]);
        $ev = $stmt->fetch();
        if (!$ev) throw new RuntimeException('That match is no longer open.');

        $map = [
            'home' => [$ev['odds_home'], $ev['home'] . ' to win'],
            'draw' => [$ev['odds_draw'], 'Draw'],
            'away' => [$ev['odds_away'], $ev['away'] . ' to win'],
        ];
        if (!isset($map[$pick]) || $map[$pick][0] === null) throw new RuntimeException('Invalid selection.');

        [$odds, $label] = $map[$pick];
        $selection = $ev['home'] . ' vs ' . $ev['away'] . ' — ' . $label;
        place_bet($pdo, (int)current_user($pdo)['id'], 'sports', $selection, $stake, (float)$odds, $eventId);
        flash('Bet placed! ' . e($selection) . ' @ ' . number_format($odds, 2) . ' 🐝', 'success');
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    header('Location: sports.php');
    exit;
}

$events = $pdo->query('SELECT * FROM events WHERE status = "open" ORDER BY starts_at')->fetchAll();
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">⚽ Sports Betting</h2>
<p class="muted">Back the home win, the draw or the away side. Odds include the house margin — that's how the hive earns its honey.</p>

<?php if (!is_logged_in()): ?>
  <div class="flash flash--info" style="margin:16px 0"><a href="login.php" style="color:#bfe0ff;font-weight:800">Log in</a> or <a href="register.php" style="color:#bfe0ff;font-weight:800">join</a> to place bets.</div>
<?php endif; ?>

<div class="card mt">
<?php foreach ($events as $ev): ?>
  <form method="post" class="event">
    <?= csrf_field() ?>
    <input type="hidden" name="event_id" value="<?= (int)$ev['id'] ?>">
    <div class="event__teams">
      <div class="pill" style="margin-bottom:6px"><?= e($ev['league']) ?></div>
      <b><?= e($ev['home']) ?> <span class="muted">vs</span> <?= e($ev['away']) ?></b>
      <div class="event__meta">⏱ <?= date('D d M · H:i', strtotime($ev['starts_at'])) ?></div>
    </div>
    <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
      <button class="odds-btn" name="pick" value="home"><small>1 · Home</small><?= number_format($ev['odds_home'], 2) ?></button>
      <?php if ($ev['odds_draw'] !== null): ?>
      <button class="odds-btn" name="pick" value="draw"><small>X · Draw</small><?= number_format($ev['odds_draw'], 2) ?></button>
      <?php endif; ?>
      <button class="odds-btn" name="pick" value="away"><small>2 · Away</small><?= number_format($ev['odds_away'], 2) ?></button>
      <input type="number" name="stake" step="0.01" min="1" value="10" style="width:90px;padding:11px;border-radius:11px;background:var(--bg-2);border:1px solid var(--line);color:var(--text)" aria-label="Stake">
    </div>
  </form>
<?php endforeach; ?>
<?php if (!$events): ?><p class="muted center">No open matches right now — check back soon. 🐝</p><?php endif; ?>
</div>

<div class="disclaimer">Tip: to place a bet, set your stake then click the odds you want. Winnings = stake × odds. Demo credits only.</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
