<?php
require_once __DIR__ . '/includes/guard.php';
$pageTitle = 'Dashboard';
require __DIR__ . '/includes/header.php';

$fin = financials();
$pf  = portfolio_stats();
$inv = invoice_stats();

$clients   = (int) scalar('SELECT COUNT(*) FROM clients');
$activeEng = rows("SELECT * FROM engagements WHERE status = 'active'");
$activeFees = array_sum(array_column($activeEng, 'fee'));
$pipeline  = (float) scalar("SELECT COALESCE(SUM(fee),0) FROM engagements WHERE status = 'proposal'");
$payroll   = (float) scalar('SELECT COALESCE(SUM(gross),0) FROM employees');

$openFindings = rows("SELECT * FROM findings WHERE status = 'open'");
$crit = 0; foreach ($openFindings as $f) { if ($f['severity'] === 'critical' || $f['severity'] === 'high') $crit++; }

$openRisks = (int) scalar("SELECT COUNT(*) FROM risks WHERE status = 'open'");
$highRisks = (int) scalar("SELECT COUNT(*) FROM risks WHERE status = 'open' AND likelihood * impact >= 15");

$pending  = rows("SELECT * FROM obligations WHERE status = 'pending'");
$dueSoon = 0; $overdue = 0;
foreach ($pending as $o) { $d = days_until($o['due_date']); if ($d < 0) $overdue++; elseif ($d <= 14) $dueSoon++; }

$activeLoops = rows("SELECT * FROM ooda WHERE status = 'active'");
$invy = inventory_stats();
$pay  = payment_stats();
$upcoming = rows("SELECT * FROM obligations WHERE status = 'pending' ORDER BY due_date ASC LIMIT 6");
$STAGES = ['Observe', 'Orient', 'Decide', 'Act'];
?>
<div class="view-head">
  <div><h1>Command Dashboard</h1>
    <div class="sub">Every practice area at a glance — observe first, then act.</div></div>
  <div class="head-actions"><a class="btn btn-primary" href="ooda.php">⟳ Run OODA Loop</a></div>
</div>

<div class="grid grid-4">
  <div class="stat accent"><div class="label">Clients</div><div class="value"><?= $clients ?></div>
    <div class="hint"><?= count($activeEng) ?> active engagement<?= count($activeEng) === 1 ? '' : 's' ?></div></div>
  <div class="stat <?= $fin['netIncome'] >= 0 ? 'good' : 'bad' ?>"><div class="label">Net Income (books)</div>
    <div class="value"><?= money($fin['netIncome']) ?></div>
    <div class="hint"><?= (int) scalar('SELECT COUNT(*) FROM journal') ?> journal entries</div></div>
  <div class="stat"><div class="label">Loan Portfolio</div><div class="value"><?= money($pf['outstanding']) ?></div>
    <div class="hint"><?= $pf['count'] ?> active loans</div></div>
  <div class="stat <?= $pf['parPct'] > 5 ? 'bad' : 'good' ?>"><div class="label">PAR &gt; 30 days</div>
    <div class="value"><?= fnum($pf['parPct']) ?>%</div><div class="hint">target &lt; 5%</div></div>
  <div class="stat <?= $crit ? 'bad' : 'good' ?>"><div class="label">Open Audit Findings</div>
    <div class="value"><?= count($openFindings) ?></div><div class="hint"><?= $crit ?> high / critical</div></div>
  <div class="stat <?= $highRisks ? 'warn' : '' ?>"><div class="label">Open Risks</div>
    <div class="value"><?= $openRisks ?></div><div class="hint"><?= $highRisks ?> severe (score ≥ 15)</div></div>
  <div class="stat <?= $overdue ? 'bad' : ($dueSoon ? 'warn' : 'good') ?>"><div class="label">Compliance</div>
    <div class="value"><?= $overdue ? $overdue . ' overdue' : $dueSoon . ' due soon' ?></div>
    <div class="hint">next 14 days window</div></div>
  <div class="stat <?= $pay['pendCount'] ? 'warn' : 'good' ?>"><div class="label">Payments to Sign</div>
    <div class="value"><?= $pay['pendCount'] ?></div><div class="hint"><?= money($pay['pendAmt']) ?> awaiting sign-off</div></div>
  <div class="stat <?= $invy['out'] ? 'bad' : ($invy['low'] ? 'warn' : 'good') ?>"><div class="label">Inventory Alerts</div>
    <div class="value"><?= $invy['alerts'] ?></div><div class="hint"><?= $invy['out'] ?> out, <?= $invy['low'] ?> low · <?= money($invy['value']) ?> value</div></div>
  <div class="stat accent"><div class="label">Active OODA Loops</div><div class="value"><?= count($activeLoops) ?></div>
    <div class="hint">decision cycles in flight</div></div>
</div>

<div class="card mt">
  <h3>Cash Flow — last 6 months (per books)</h3>
  <?= cashflow_chart_html(cashflow_series(6)) ?>
</div>

<div class="grid grid-2 mt">
  <div class="card">
    <h3>Revenue Snapshot</h3>
    <div class="report-line"><span>Active engagement fees</span><span class="amt"><?= money($activeFees) ?></span></div>
    <div class="report-line"><span>Proposal pipeline</span><span class="amt"><?= money($pipeline) ?></span></div>
    <div class="report-line"><span>Unpaid invoices</span><span class="amt"><?= money($inv['outstanding']) ?></span></div>
    <div class="report-line"><span>&nbsp;&nbsp;of which overdue</span>
      <span class="amt <?= $inv['overdue'] ? 'neg' : '' ?>"><?= money($inv['overdue']) ?></span></div>
    <div class="report-line"><span>Monthly payroll cost</span><span class="amt neg"><?= money($payroll) ?></span></div>
    <div class="report-line total"><span>Net income per books</span>
      <span class="amt <?= $fin['netIncome'] >= 0 ? 'pos' : 'neg' ?>"><?= money($fin['netIncome']) ?></span></div>
  </div>
  <div class="card">
    <h3>Upcoming Compliance Deadlines</h3>
    <?php if ($upcoming): ?>
      <div class="tbl-wrap"><table>
        <tr><th>Obligation</th><th>Due</th><th></th></tr>
        <?php foreach ($upcoming as $o): $d = days_until($o['due_date']); ?>
          <tr><td><?= e($o['name']) ?><div class="muted" style="font-size:11px"><?= e($o['authority']) ?></div></td>
            <td><?= e($o['due_date']) ?></td>
            <td><?php if ($d < 0) echo badge((-$d) . 'd overdue', 'b-red');
                      elseif ($d <= 14) echo badge($d . 'd left', 'b-amber');
                      else echo badge($d . 'd', 'b-grey'); ?></td></tr>
        <?php endforeach; ?>
      </table></div>
    <?php else: ?>
      <div class="empty">No pending obligations. Add them in Tax &amp; Compliance.</div>
    <?php endif; ?>
  </div>
</div>

<div class="card mt">
  <h3>Active OODA Loops</h3>
  <?php if ($activeLoops): foreach ($activeLoops as $o): ?>
    <div class="report-line"><span><strong><?= e($o['title']) ?></strong>
      <span class="muted"> — cycle <?= (int) $o['cycles'] + 1 ?>, stage: </span>
      <?= badge($STAGES[(int) $o['stage']], 'b-gold') ?></span>
      <a class="btn btn-sm" href="ooda.php">Open</a></div>
  <?php endforeach; else: ?>
    <div class="empty">No active decision loops. Every big call should run through OODA.</div>
  <?php endif; ?>
</div>

<?php require __DIR__ . '/includes/footer.php'; ?>
