<?php
require_once __DIR__ . '/includes/functions.php';

if (is_post()) {
    switch (post('action')) {
        case 'emp-new':
            insert('INSERT INTO employees (name, role, gross, deduct_pct) VALUES (?,?,?,?)',
                [post('name'), post('role'), (float) post('gross'), (float) post('deduct_pct', 15)]);
            redirect('hr.php', 'Employee added.');
        case 'emp-del':
            q('DELETE FROM employees WHERE id = ?', [(int) post('id')]);
            redirect('hr.php', 'Employee removed.');
    }
    redirect('hr.php');
}

$pageTitle = 'HR & Payroll';
require __DIR__ . '/includes/header.php';
$emps = rows('SELECT * FROM employees ORDER BY name');
$totalGross = array_sum(array_column($emps, 'gross'));
$totalNet = 0;
foreach ($emps as $emp) { $totalNet += (float) $emp['gross'] * (1 - (float) $emp['deduct_pct'] / 100); }
?>
<div class="view-head">
  <div><h1>HR &amp; Payroll</h1>
    <div class="sub">Headcount and monthly payroll with statutory deduction estimates.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('emp-form').showModal()">+ Employee</button></div>
</div>

<div class="grid grid-4">
  <div class="stat"><div class="label">Headcount</div><div class="value"><?= count($emps) ?></div></div>
  <div class="stat accent"><div class="label">Gross Payroll / mo</div><div class="value"><?= money($totalGross) ?></div></div>
  <div class="stat"><div class="label">Net Payroll / mo</div><div class="value"><?= money($totalNet) ?></div></div>
  <div class="stat"><div class="label">Deductions / mo</div><div class="value"><?= money($totalGross - $totalNet) ?></div></div>
</div>

<div class="card mt">
  <h3>Employees</h3>
  <?php if ($emps): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Name</th><th>Role</th><th class="num">Gross / mo</th><th class="num">Deductions</th><th class="num">Net Pay</th><th></th></tr>
      <?php foreach ($emps as $emp): $ded = (float) $emp['gross'] * (float) $emp['deduct_pct'] / 100; ?>
        <tr><td><strong><?= e($emp['name']) ?></strong></td><td><?= e($emp['role'] ?: '—') ?></td>
          <td class="num"><?= money($emp['gross']) ?></td>
          <td class="num"><?= money($ded) ?> <span class="muted">(<?= fnum($emp['deduct_pct']) ?>%)</span></td>
          <td class="num"><?= money((float) $emp['gross'] - $ded) ?></td>
          <td><form method="post" style="display:inline" data-confirm="Delete this employee?">
            <input type="hidden" name="action" value="emp-del"><input type="hidden" name="id" value="<?= $emp['id'] ?>">
            <button class="btn btn-icon">✕</button></form></td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No employees on payroll.</div><?php endif; ?>
</div>

<dialog id="emp-form" class="dlg"><form method="post">
  <h2>New Employee</h2><input type="hidden" name="action" value="emp-new">
  <label>Name *</label><input name="name" required>
  <label>Role</label><input name="role">
  <div class="form-row">
    <div><label>Gross salary / month *</label><input name="gross" type="number" step="any" min="0" required></div>
    <div><label>Deductions % (tax + social)</label><input name="deduct_pct" type="number" step="any" min="0" max="100" value="15"></div>
  </div>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<?php require __DIR__ . '/includes/footer.php'; ?>
