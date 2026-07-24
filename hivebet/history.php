<?php
require_once __DIR__ . '/includes/functions.php';
require_login();
$__page = 'Bet History';
$user = current_user($pdo);

$bets = $pdo->prepare('SELECT * FROM bets WHERE user_id = ? ORDER BY id DESC LIMIT 100');
$bets->execute([$user['id']]);
$bets = $bets->fetchAll();

$agg = $pdo->prepare(
    'SELECT COUNT(*) c, COALESCE(SUM(stake),0) staked, COALESCE(SUM(payout),0) paid,
            SUM(status="won") wins, SUM(status="lost") losses
     FROM bets WHERE user_id = ?'
);
$agg->execute([$user['id']]);
$s = $agg->fetch();
$net = (float)$s['paid'] - (float)$s['staked'];
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">📜 Bet History</h2>

<div class="stats">
  <div class="stat"><b><?= (int)$s['c'] ?></b><span>Total bets</span></div>
  <div class="stat"><b><?= (int)$s['wins'] ?>W / <?= (int)$s['losses'] ?>L</b><span>Win / loss</span></div>
  <div class="stat"><b><?= money($s['staked']) ?></b><span>Total staked</span></div>
  <div class="stat"><b class="<?= $net >= 0 ? 'pos' : 'neg' ?>"><?= ($net >= 0 ? '+' : '') . money($net) ?></b><span>Net result</span></div>
</div>

<div class="card mt">
  <table class="table">
    <tr><th>#</th><th>Game</th><th>Selection</th><th>Stake</th><th>Odds</th><th>Result</th><th>Payout</th><th>Status</th><th>When</th></tr>
    <?php foreach ($bets as $b): ?>
      <tr>
        <td class="muted"><?= (int)$b['id'] ?></td>
        <td><?= e(ucfirst($b['game'])) ?></td>
        <td><?= e($b['selection']) ?><?php if ($b['result']): ?><br><span class="muted" style="font-size:.78rem"><?= e($b['result']) ?></span><?php endif; ?></td>
        <td><?= money($b['stake']) ?></td>
        <td><?= number_format($b['odds'], 2) ?></td>
        <td class="muted"><?= e($b['result'] ?? '—') ?></td>
        <td class="<?= $b['payout'] > 0 ? 'pos' : '' ?>"><?= $b['payout'] > 0 ? money($b['payout']) : '—' ?></td>
        <td><span class="badge badge--<?= e($b['status']) ?>"><?= e(ucfirst($b['status'])) ?></span></td>
        <td class="muted"><?= date('d M H:i', strtotime($b['created_at'])) ?></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$bets): ?><tr><td colspan="9" class="muted center">No bets yet — go place one! 🐝</td></tr><?php endif; ?>
  </table>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
