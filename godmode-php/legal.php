<?php
require_once __DIR__ . '/includes/functions.php';
require_once __DIR__ . '/includes/auth.php';
auth_boot();
require_login();                       // both roles may read the library
log_usage('visit', 'legal.php');

$pageTitle = 'Zimbabwe Law';
require __DIR__ . '/includes/header.php';
$kb = zim_legal_kb();
?>
<div class="view-head">
  <div><h1>Zimbabwe Business Law &amp; Compliance</h1>
    <div class="sub">Statutes, authorities and obligations that shape the app's guidance. The AI Advisor draws on this.</div></div>
</div>

<div class="card" style="border-color:rgba(224,166,58,.4)">
  <strong>⚠ Use as structural guidance, not legal advice.</strong>
  <div class="muted" style="font-size:12.5px;margin-top:4px">
    Rates, thresholds and deadlines in Zimbabwe change frequently (often each national Budget / Finance Act).
    Always confirm the current figure with the named authority (ZIMRA, NSSA, ZIMDEF, the Registrar, POTRAZ) before you act.
  </div>
</div>

<div class="grid grid-2 mt">
  <?php foreach ($kb as $t): ?>
    <div class="card" id="<?= e($t['key']) ?>">
      <h3 style="text-transform:none;color:var(--accent-2);font-size:15px"><?= e($t['title']) ?></h3>
      <div class="muted" style="font-size:12px;margin:-4px 0 10px">
        <?= e($t['authority']) ?> · <span class="mono"><?= e($t['act']) ?></span>
      </div>
      <p style="font-size:13px;margin-bottom:8px"><?= e($t['summary']) ?></p>
      <ul style="list-style:none;font-size:12.8px">
        <?php foreach ($t['obligations'] as $o): ?>
          <li style="padding:3px 0">• <?= e($o) ?></li>
        <?php endforeach; ?>
      </ul>
      <div class="badge b-amber" style="margin-top:8px">Verify: <?= e($t['verify']) ?></div>
    </div>
  <?php endforeach; ?>
</div>

<?php require __DIR__ . '/includes/footer.php'; ?>
