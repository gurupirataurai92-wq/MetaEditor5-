<?php
require_once __DIR__ . '/includes/functions.php';

if (is_post()) {
    switch (post('action')) {
        case 'obl-new':
            $cid = post('client_id') !== '' ? (int) post('client_id') : null;
            insert('INSERT INTO obligations (name, authority, client_id, due_date, frequency, status) VALUES (?,?,?,?,?,?)',
                [post('name'), post('authority'), $cid, post('due_date', today()), post('frequency', 'one-off'), 'pending']);
            redirect('tax.php', 'Obligation tracked.');
        case 'obl-file':
            q("UPDATE obligations SET status = 'filed' WHERE id = ?", [(int) post('id')]);
            redirect('tax.php', 'Marked as filed.');
        case 'obl-del':
            q('DELETE FROM obligations WHERE id = ?', [(int) post('id')]);
            redirect('tax.php', 'Obligation removed.');
    }
    redirect('tax.php');
}

$pageTitle = 'Tax & Compliance';
require __DIR__ . '/includes/header.php';
$obls = rows('SELECT * FROM obligations ORDER BY due_date ASC');
$clients = rows('SELECT id, name FROM clients ORDER BY name');
?>
<div class="view-head">
  <div><h1>Tax &amp; Compliance</h1>
    <div class="sub">Filing calendar and statutory obligations — never miss a deadline.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('obl-form').showModal()">+ Obligation</button></div>
</div>

<div class="card">
  <h3>Obligations</h3>
  <?php if ($obls): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Obligation</th><th>Authority</th><th>Client</th><th>Due</th><th>Frequency</th><th>Status</th><th></th></tr>
      <?php foreach ($obls as $o): $d = days_until($o['due_date']); ?>
        <tr><td><strong><?= e($o['name']) ?></strong></td><td><?= e($o['authority'] ?: '—') ?></td>
          <td><?= e(client_name($o['client_id'] !== null ? (int) $o['client_id'] : null)) ?></td>
          <td><?= e($o['due_date']) ?>
            <?php if ($o['status'] === 'pending') { if ($d < 0) echo ' ' . badge((-$d) . 'd overdue', 'b-red'); elseif ($d <= 14) echo ' ' . badge($d . 'd', 'b-amber'); } ?></td>
          <td><?= e($o['frequency']) ?></td>
          <td><?= $o['status'] === 'pending' ? badge('pending', 'b-amber') : badge('filed', 'b-green') ?></td>
          <td style="white-space:nowrap">
            <?php if ($o['status'] === 'pending'): ?>
            <form method="post" style="display:inline"><input type="hidden" name="action" value="obl-file">
              <input type="hidden" name="id" value="<?= $o['id'] ?>"><button class="btn btn-icon" title="mark filed">✓</button></form>
            <?php endif; ?>
            <form method="post" style="display:inline" data-confirm="Delete this obligation?"><input type="hidden" name="action" value="obl-del">
              <input type="hidden" name="id" value="<?= $o['id'] ?>"><button class="btn btn-icon">✕</button></form>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No obligations tracked. Add VAT returns, payroll taxes, license renewals, AGM filings…</div><?php endif; ?>
</div>

<dialog id="obl-form" class="dlg"><form method="post">
  <h2>New Obligation</h2><input type="hidden" name="action" value="obl-new">
  <label>Obligation *</label><input name="name" placeholder="VAT return, PAYE, license renewal…" required>
  <div class="form-row">
    <div><label>Authority</label><input name="authority" placeholder="Revenue authority…"></div>
    <div><label>Client</label><select name="client_id"><option value="">— none / internal —</option>
      <?php foreach ($clients as $c) echo '<option value="' . $c['id'] . '">' . e($c['name']) . '</option>'; ?>
    </select></div>
  </div>
  <div class="form-row">
    <div><label>Due date *</label><input name="due_date" type="date" required></div>
    <div><label>Frequency</label><select name="frequency"><option>one-off</option><option>monthly</option><option>quarterly</option><option>annual</option></select></div>
  </div>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<?php require __DIR__ . '/includes/footer.php'; ?>
