<?php
require_once __DIR__ . '/includes/guard.php';

if (is_post()) {
    switch (post('action')) {
        case 'loan-new':
            insert('INSERT INTO loans (borrower, principal, rate, months, method, repaid, days_overdue, status, start_date)
                    VALUES (?,?,?,?,?,?,?,?,?)',
                [post('borrower'), (float) post('principal'), (float) post('rate'), (int) post('months', 12),
                 post('method', 'declining'), 0, (int) post('days_overdue'), 'active', today()]);
            redirect('microfinance.php', 'Loan booked.');
        case 'loan-pay':
            $l = one('SELECT * FROM loans WHERE id = ?', [(int) post('id')]);
            if ($l) {
                $repaid = (float) $l['repaid'] + (float) post('amt');
                $od = (int) post('od');
                q('UPDATE loans SET repaid = ?, days_overdue = ? WHERE id = ?', [$repaid, $od, $l['id']]);
                $l['repaid'] = $repaid;
                if (loan_outstanding($l) <= 0.005) {
                    q("UPDATE loans SET status = 'closed', days_overdue = 0 WHERE id = ?", [$l['id']]);
                    redirect('microfinance.php', 'Loan fully repaid — closed.');
                }
                redirect('microfinance.php', 'Repayment recorded.');
            }
            redirect('microfinance.php');
        case 'loan-del':
            q('DELETE FROM loans WHERE id = ?', [(int) post('id')]);
            redirect('microfinance.php', 'Loan removed.');
    }
    redirect('microfinance.php');
}

$pageTitle = 'Microfinance';
require __DIR__ . '/includes/header.php';
$pf = portfolio_stats();
$loans = rows('SELECT * FROM loans ORDER BY id DESC');
$closed = count(array_filter($loans, fn($l) => $l['status'] === 'closed'));
?>
<div class="view-head">
  <div><h1>Microfinance</h1>
    <div class="sub">Loan book, amortization schedules and portfolio-at-risk monitoring.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('loan-form').showModal()">+ Loan</button></div>
</div>

<div class="grid grid-4">
  <div class="stat"><div class="label">Active Loans</div><div class="value"><?= $pf['count'] ?></div></div>
  <div class="stat accent"><div class="label">Outstanding</div><div class="value"><?= money($pf['outstanding']) ?></div></div>
  <div class="stat <?= $pf['parPct'] > 5 ? 'bad' : 'good' ?>"><div class="label">PAR &gt; 30</div><div class="value"><?= fnum($pf['parPct']) ?>%</div>
    <div class="hint"><?= money($pf['par30']) ?> at risk</div></div>
  <div class="stat"><div class="label">Closed Loans</div><div class="value"><?= $closed ?></div></div>
</div>

<div class="card mt">
  <h3>Loan Book</h3>
  <?php if ($loans): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Borrower</th><th class="num">Principal</th><th class="num">Rate</th><th class="num">Months</th>
        <th>Method</th><th class="num">Repaid</th><th class="num">Outstanding</th><th>Overdue</th><th>Status</th><th></th></tr>
      <?php foreach ($loans as $l): $od = (int) $l['days_overdue']; $sch = loan_schedule($l); ?>
        <tr><td><strong><?= e($l['borrower']) ?></strong></td>
          <td class="num"><?= money($l['principal']) ?></td><td class="num"><?= fnum($l['rate']) ?>%</td><td class="num"><?= (int) $l['months'] ?></td>
          <td><?= e($l['method']) ?></td><td class="num"><?= money($l['repaid']) ?></td>
          <td class="num"><?= money(loan_outstanding($l)) ?></td>
          <td><?php echo $od > 30 ? badge($od . 'd', 'b-red') : ($od > 0 ? badge($od . 'd', 'b-amber') : badge('current', 'b-green')); ?></td>
          <td><?= $l['status'] === 'active' ? badge('active', 'b-gold') : badge('closed', 'b-grey') ?></td>
          <td style="white-space:nowrap">
            <button class="btn btn-icon" title="schedule"
              onclick='showSched(<?= json_encode([
                'borrower' => $l['borrower'], 'method' => $l['method'],
                'payment' => money($sch['payment']), 'interest' => money($sch['totalInterest']), 'due' => money($sch['totalDue']),
                'rows' => array_map(fn($r) => [$r['m'], fnum($r['payment']), fnum($r['principal']), fnum($r['interest']), fnum($r['balance'])], $sch['rows'])
              ], JSON_HEX_APOS | JSON_HEX_QUOT) ?>)'>▤</button>
            <?php if ($l['status'] === 'active'): ?>
            <button class="btn btn-icon" title="record repayment"
              onclick='payLoan(<?= json_encode(['id' => $l['id'], 'borrower' => $l['borrower'], 'outstanding' => money(loan_outstanding($l)), 'od' => $od], JSON_HEX_APOS | JSON_HEX_QUOT) ?>)'>＋</button>
            <?php endif; ?>
            <form method="post" style="display:inline" data-confirm="Delete this loan?"><input type="hidden" name="action" value="loan-del">
              <input type="hidden" name="id" value="<?= $l['id'] ?>"><button class="btn btn-icon">✕</button></form>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No loans yet. Add one to generate its amortization schedule automatically.</div><?php endif; ?>
</div>

<dialog id="loan-form" class="dlg"><form method="post">
  <h2>New Loan</h2><input type="hidden" name="action" value="loan-new">
  <label>Borrower *</label><input name="borrower" required>
  <div class="form-row-3">
    <div><label>Principal *</label><input name="principal" type="number" step="any" min="1" required></div>
    <div><label>Annual rate %</label><input name="rate" type="number" step="any" value="24"></div>
    <div><label>Term (months)</label><input name="months" type="number" min="1" value="12"></div>
  </div>
  <div class="form-row">
    <div><label>Interest method</label><select name="method"><option value="declining">Declining balance</option><option value="flat">Flat rate</option></select></div>
    <div><label>Days overdue</label><input name="days_overdue" type="number" min="0" value="0"></div>
  </div>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Book loan</button></div>
</form></dialog>

<dialog id="sched-dlg" class="dlg">
  <h2 id="sched-title">Amortization</h2>
  <div class="muted" id="sched-sub" style="font-size:12.5px;margin-bottom:10px"></div>
  <div class="tbl-wrap" style="max-height:340px;overflow-y:auto"><table id="sched-table"></table></div>
  <div class="modal-actions"><button class="btn" onclick="this.closest('dialog').close()">Close</button></div>
</dialog>

<dialog id="pay-dlg" class="dlg"><form method="post">
  <h2 id="pay-title">Record Repayment</h2><input type="hidden" name="action" value="loan-pay"><input type="hidden" name="id" id="pay-id">
  <div class="muted" id="pay-sub" style="font-size:12.5px"></div>
  <label>Amount received *</label><input name="amt" type="number" step="any" min="0.01" required>
  <label>Days overdue after payment</label><input name="od" id="pay-od" type="number" min="0" value="0">
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Record</button></div>
</form></dialog>

<script>
function showSched(l) {
  document.getElementById('sched-title').textContent = 'Amortization — ' + l.borrower;
  document.getElementById('sched-sub').innerHTML = l.method + ' · payment ≈ <strong>' + l.payment +
    '</strong>/mo · total interest <strong>' + l.interest + '</strong> · total due <strong>' + l.due + '</strong>';
  var h = '<tr><th>#</th><th class="num">Payment</th><th class="num">Principal</th><th class="num">Interest</th><th class="num">Balance</th></tr>';
  l.rows.forEach(function (r) {
    h += '<tr><td>' + r[0] + '</td><td class="num">' + r[1] + '</td><td class="num">' + r[2] + '</td><td class="num">' + r[3] + '</td><td class="num">' + r[4] + '</td></tr>';
  });
  document.getElementById('sched-table').innerHTML = h;
  document.getElementById('sched-dlg').showModal();
}
function payLoan(l) {
  document.getElementById('pay-title').textContent = 'Record Repayment — ' + l.borrower;
  document.getElementById('pay-sub').innerHTML = 'Outstanding: <strong>' + l.outstanding + '</strong>';
  document.getElementById('pay-id').value = l.id;
  document.getElementById('pay-od').value = l.od;
  document.getElementById('pay-dlg').showModal();
}
</script>

<?php require __DIR__ . '/includes/footer.php'; ?>
