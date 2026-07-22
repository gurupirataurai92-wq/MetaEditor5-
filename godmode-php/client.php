<?php
require_once __DIR__ . '/includes/functions.php';
$id = (int) getp('id');
$c = one('SELECT * FROM clients WHERE id = ?', [$id]);
if (!$c) { http_response_code(404); echo 'Client not found.'; exit; }

$h = client_health($id);
$eng = rows('SELECT * FROM engagements WHERE client_id = ?', [$id]);
$won = array_filter($eng, fn($e) => $e['status'] !== 'proposal');
$fees = array_sum(array_column($won, 'fee'));
$proposals = count(array_filter($eng, fn($e) => $e['status'] === 'proposal'));
$unpaid = 0;
foreach ($h['invs'] as $i) { if ($i['status'] !== 'paid') $unpaid += invoice_total((int) $i['id']); }
$gradeCls = $h['score'] >= 70 ? 'pos' : ($h['score'] >= 55 ? '' : 'neg');

$pageTitle = '360° — ' . $c['name'];
require __DIR__ . '/includes/header.php';
?>
<div class="view-head no-print">
  <div><h1>360° Report — <?= e($c['name']) ?></h1>
    <div class="sub"><a href="consulting.php">← back to CRM</a> · <?= e($c['industry'] ?: '') ?> · generated <?= today() ?></div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="window.print()">Print / PDF</button></div>
</div>

<div class="card">
  <div style="display:flex;gap:24px;align-items:center;margin-bottom:16px;flex-wrap:wrap">
    <div>
      <div class="health-ring <?= $gradeCls ?>"><?= $h['score'] ?></div>
      <div class="health-grade <?= $gradeCls ?>">GRADE <?= $h['grade'] ?></div>
    </div>
    <div style="flex:1;min-width:240px">
      <?php if ($h['notes']): foreach ($h['notes'] as $n): ?>
        <div class="report-line"><span>⚠ <?= e($n) ?></span></div>
      <?php endforeach; else: ?>
        <div class="muted">No red flags detected across audits, invoicing, compliance or the risk register.</div>
      <?php endif; ?>
    </div>
  </div>
  <div class="report-line"><span>Engagements (won)</span><span class="amt"><?= count($won) ?> · <?= money($fees) ?></span></div>
  <div class="report-line"><span>Open proposals</span><span class="amt"><?= $proposals ?></span></div>
  <div class="report-line"><span>Unpaid invoices</span><span class="amt"><?= money($unpaid) ?></span></div>
  <div class="report-line"><span>Open audit findings</span><span class="amt"><?= count($h['findings']) ?></span></div>
</div>

<?php require __DIR__ . '/includes/footer.php'; ?>
