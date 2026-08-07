<?php
require_once __DIR__ . '/includes/guard.php';

$AUDIT_STAGES = ['planning', 'fieldwork', 'reporting', 'closed'];

if (is_post()) {
    switch (post('action')) {
        case 'audit-new':
            insert('INSERT INTO audits (client_id, scope, period, status) VALUES (?,?,?,?)',
                [(int) post('client_id'), post('scope'), post('period'), 'planning']);
            redirect('auditing.php', 'Audit created.');
        case 'audit-next':
            $st = scalar('SELECT status FROM audits WHERE id = ?', [(int) post('id')]);
            $i = array_search($st, $AUDIT_STAGES, true);
            $next = $AUDIT_STAGES[min(($i === false ? 0 : $i) + 1, 3)];
            q('UPDATE audits SET status = ? WHERE id = ?', [$next, (int) post('id')]);
            redirect('auditing.php');
        case 'audit-del':
            q('DELETE FROM audits WHERE id = ?', [(int) post('id')]);
            redirect('auditing.php', 'Audit removed.');
        case 'finding-new':
            insert('INSERT INTO findings (audit_id, title, severity, recommendation, status) VALUES (?,?,?,?,?)',
                [(int) post('audit_id'), post('title'), post('severity', 'medium'), post('recommendation'), 'open']);
            redirect('auditing.php', 'Finding logged.');
        case 'finding-resolve':
            q("UPDATE findings SET status = 'resolved' WHERE id = ?", [(int) post('id')]);
            redirect('auditing.php', 'Finding resolved.');
        case 'finding-del':
            q('DELETE FROM findings WHERE id = ?', [(int) post('id')]);
            redirect('auditing.php', 'Finding removed.');
    }
    redirect('auditing.php');
}

$pageTitle = 'Auditing';
require __DIR__ . '/includes/header.php';
$audits = rows('SELECT * FROM audits ORDER BY id DESC');
$findings = rows('SELECT * FROM findings ORDER BY id DESC');
$open = array_filter($findings, fn($f) => $f['status'] === 'open');
$sevCls = fn($s) => ['critical' => 'b-red', 'high' => 'b-red', 'medium' => 'b-amber', 'low' => 'b-blue'][$s] ?? 'b-grey';
?>
<div class="view-head">
  <div><h1>Audit Practice</h1>
    <div class="sub">Engagement tracking, findings log and remediation status.</div></div>
  <div class="head-actions">
    <button class="btn" onclick="document.getElementById('finding-form').showModal()" <?= $audits ? '' : 'disabled' ?>>+ Finding</button>
    <button class="btn btn-primary" onclick="document.getElementById('audit-form').showModal()">+ Audit</button>
  </div>
</div>

<div class="grid grid-4">
  <div class="stat"><div class="label">Audits</div><div class="value"><?= count($audits) ?></div></div>
  <div class="stat <?= $open ? 'warn' : 'good' ?>"><div class="label">Open Findings</div><div class="value"><?= count($open) ?></div></div>
  <div class="stat <?= array_filter($open, fn($f) => $f['severity'] === 'critical') ? 'bad' : 'good' ?>">
    <div class="label">Critical Open</div>
    <div class="value"><?= count(array_filter($open, fn($f) => $f['severity'] === 'critical')) ?></div></div>
  <div class="stat"><div class="label">Resolved</div>
    <div class="value"><?= count(array_filter($findings, fn($f) => $f['status'] === 'resolved')) ?></div></div>
</div>

<div class="card mt">
  <h3>Audit Engagements</h3>
  <?php if ($audits): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Client</th><th>Scope</th><th>Period</th><th>Stage</th><th></th></tr>
      <?php foreach ($audits as $a): ?>
        <tr><td><?= e(client_name((int) $a['client_id'])) ?></td><td><?= e($a['scope']) ?></td><td><?= e($a['period']) ?></td>
          <td><?= badge($a['status'], $a['status'] === 'closed' ? 'b-grey' : 'b-gold') ?></td>
          <td style="white-space:nowrap">
            <?php if ($a['status'] !== 'closed'): ?>
            <form method="post" style="display:inline"><input type="hidden" name="action" value="audit-next">
              <input type="hidden" name="id" value="<?= $a['id'] ?>"><button class="btn btn-icon" title="advance stage">→</button></form>
            <?php endif; ?>
            <form method="post" style="display:inline" data-confirm="Delete this audit?"><input type="hidden" name="action" value="audit-del">
              <input type="hidden" name="id" value="<?= $a['id'] ?>"><button class="btn btn-icon">✕</button></form>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No audits yet.</div><?php endif; ?>
</div>

<div class="card mt">
  <h3>Findings Register</h3>
  <?php if ($findings): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Finding</th><th>Audit</th><th>Severity</th><th>Recommendation</th><th>Status</th><th></th></tr>
      <?php foreach ($findings as $f):
        $a = one('SELECT * FROM audits WHERE id = ?', [(int) $f['audit_id']]); ?>
        <tr><td><strong><?= e($f['title']) ?></strong></td>
          <td><?= $a ? e(client_name((int) $a['client_id']) . ' · ' . $a['period']) : '—' ?></td>
          <td><?= badge($f['severity'], $sevCls($f['severity'])) ?></td>
          <td><?= e($f['recommendation'] ?: '—') ?></td>
          <td><?= $f['status'] === 'open' ? badge('open', 'b-amber') : badge('resolved', 'b-green') ?></td>
          <td style="white-space:nowrap">
            <?php if ($f['status'] === 'open'): ?>
            <form method="post" style="display:inline"><input type="hidden" name="action" value="finding-resolve">
              <input type="hidden" name="id" value="<?= $f['id'] ?>"><button class="btn btn-icon" title="resolve">✓</button></form>
            <?php endif; ?>
            <form method="post" style="display:inline" data-confirm="Delete this finding?"><input type="hidden" name="action" value="finding-del">
              <input type="hidden" name="id" value="<?= $f['id'] ?>"><button class="btn btn-icon">✕</button></form>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No findings recorded.</div><?php endif; ?>
</div>

<dialog id="audit-form" class="dlg"><form method="post">
  <h2>New Audit</h2><input type="hidden" name="action" value="audit-new">
  <label>Client *</label><select name="client_id" required>
    <?php foreach (rows('SELECT id, name FROM clients ORDER BY name') as $c) echo '<option value="' . $c['id'] . '">' . e($c['name']) . '</option>'; ?>
  </select>
  <div class="form-row">
    <div><label>Scope</label><input name="scope" placeholder="Financial statements, internal controls…" required></div>
    <div><label>Period</label><input name="period" placeholder="FY2025" required></div>
  </div>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<dialog id="finding-form" class="dlg"><form method="post">
  <h2>New Finding</h2><input type="hidden" name="action" value="finding-new">
  <label>Audit *</label><select name="audit_id" required>
    <?php foreach ($audits as $a) echo '<option value="' . $a['id'] . '">' . e(client_name((int) $a['client_id']) . ' · ' . $a['period']) . '</option>'; ?>
  </select>
  <label>Finding title *</label><input name="title" required>
  <label>Severity</label><select name="severity"><option>low</option><option selected>medium</option><option>high</option><option>critical</option></select>
  <label>Recommendation</label><textarea name="recommendation"></textarea>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<?php require __DIR__ . '/includes/footer.php'; ?>
