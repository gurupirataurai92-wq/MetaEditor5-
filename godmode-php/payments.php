<?php
require_once __DIR__ . '/includes/functions.php';

if (is_post()) {
    switch (post('action')) {
        case 'pay-new':
            $cid = post('client_id') !== '' ? (int) post('client_id') : null;
            if ((float) post('amount') <= 0) redirect('payments.php', 'Amount must be positive.');
            insert('INSERT INTO payments (payee, purpose, amount, method, client_id, debit_account, credit_account,
                    status, requested_at) VALUES (?,?,?,?,?,?,?,?,?)',
                [post('payee'), post('purpose'), (float) post('amount'), post('method', 'bank'), $cid,
                 (int) post('debit_account'), (int) post('credit_account'), 'pending', today()]);
            redirect('payments.php', 'Payment requested — awaiting sign-off.');
        case 'pay-sign':
            $p = one('SELECT * FROM payments WHERE id = ?', [(int) post('id')]);
            $signer = post('signed_by');
            if ($p && $p['status'] === 'pending' && $signer !== '') {
                // Post the authorized payment to the double-entry ledger.
                $jid = insert('INSERT INTO journal (entry_date, memo, debit_account, credit_account, amount) VALUES (?,?,?,?,?)',
                    [today(), 'Payment to ' . $p['payee'] . ($p['purpose'] ? ' — ' . $p['purpose'] : '') . ' (signed: ' . $signer . ')',
                     (int) $p['debit_account'], (int) $p['credit_account'], (float) $p['amount']]);
                q("UPDATE payments SET status = 'signed', signed_by = ?, signed_at = ?, journal_id = ? WHERE id = ?",
                    [$signer, today(), $jid, $p['id']]);
                redirect('payments.php', 'Payment signed by ' . $signer . ' and posted to the books.');
            }
            redirect('payments.php', 'A signatory name is required to authorize.');
        case 'pay-reject':
            q("UPDATE payments SET status = 'rejected' WHERE id = ? AND status = 'pending'", [(int) post('id')]);
            redirect('payments.php', 'Payment rejected.');
        case 'pay-del':
            // Signed payments are locked — they are posted to the ledger and form the audit trail.
            q("DELETE FROM payments WHERE id = ? AND status <> 'signed'", [(int) post('id')]);
            redirect('payments.php', 'Payment removed.');
    }
    redirect('payments.php');
}

$pageTitle = 'Payments';
require __DIR__ . '/includes/header.php';
$stats = payment_stats();
$payments = rows('SELECT * FROM payments ORDER BY id DESC');
$clients = rows('SELECT id, name FROM clients ORDER BY name');
$accts = rows('SELECT * FROM accounts ORDER BY id');
$acctName = [];
foreach ($accts as $a) { $acctName[(int) $a['id']] = $a['name']; }
$debitOpts = ''; $creditOpts = '';
foreach ($accts as $a) {
    $tag = '<option value="' . $a['id'] . '"';
    // sensible defaults: pay FOR an expense, FROM cash/bank
    if ($a['name'] === 'Other Expenses') $debitOpts .= $tag . ' selected>' . e($a['name'] . ' (' . $a['type'] . ')') . '</option>';
    else $debitOpts .= $tag . '>' . e($a['name'] . ' (' . $a['type'] . ')') . '</option>';
    if ($a['name'] === 'Cash & Bank') $creditOpts .= $tag . ' selected>' . e($a['name'] . ' (' . $a['type'] . ')') . '</option>';
    else $creditOpts .= $tag . '>' . e($a['name'] . ' (' . $a['type'] . ')') . '</option>';
}
$methodBadge = fn($m) => ['cash' => 'b-grey', 'bank' => 'b-blue', 'mobile' => 'b-gold', 'cheque' => 'b-grey'][$m] ?? 'b-grey';
?>
<div class="view-head">
  <div><h1>Payments &amp; Authorization</h1>
    <div class="sub">Every payment is requested, then <strong>signed for</strong> inside the app before it posts to the ledger.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('pay-form').showModal()">+ Payment</button></div>
</div>

<div class="grid grid-4">
  <div class="stat <?= $stats['pendCount'] ? 'warn' : 'good' ?>"><div class="label">Awaiting Sign-off</div>
    <div class="value"><?= $stats['pendCount'] ?></div><div class="hint"><?= money($stats['pendAmt']) ?> pending</div></div>
  <div class="stat accent"><div class="label">Signed &amp; Paid</div><div class="value"><?= money($stats['signedAmt']) ?></div></div>
  <div class="stat"><div class="label">Total Payments</div><div class="value"><?= count($payments) ?></div></div>
  <div class="stat"><div class="label">Rejected</div>
    <div class="value"><?= count(array_filter($payments, fn($p) => $p['status'] === 'rejected')) ?></div></div>
</div>

<div class="card mt">
  <h3>Payment Register</h3>
  <?php if ($payments): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Payee</th><th>Purpose</th><th class="num">Amount</th><th>Method</th><th>Ledger</th>
        <th>Status</th><th>Signed for by</th><th></th></tr>
      <?php foreach ($payments as $p): ?>
        <tr><td><strong><?= e($p['payee']) ?></strong>
            <?php if ($p['client_id']): ?><div class="muted" style="font-size:11px"><?= e(client_name((int) $p['client_id'])) ?></div><?php endif; ?></td>
          <td><?= e($p['purpose'] ?: '—') ?></td>
          <td class="num"><?= money($p['amount']) ?></td>
          <td><?= badge($p['method'], $methodBadge($p['method'])) ?></td>
          <td class="muted" style="font-size:11.5px">
            <?= e($acctName[(int) $p['debit_account']] ?? '—') ?><br>← <?= e($acctName[(int) $p['credit_account']] ?? '—') ?>
          </td>
          <td><?php echo $p['status'] === 'signed' ? badge('signed ✓', 'b-green')
                    : ($p['status'] === 'rejected' ? badge('rejected', 'b-red') : badge('pending', 'b-amber')); ?></td>
          <td><?php if ($p['status'] === 'signed'): ?>
                <strong><?= e($p['signed_by']) ?></strong><div class="muted" style="font-size:11px"><?= e($p['signed_at']) ?></div>
              <?php else: ?><span class="muted">—</span><?php endif; ?></td>
          <td style="white-space:nowrap">
            <?php if ($p['status'] === 'pending'): ?>
              <button class="btn btn-icon" title="sign / authorize"
                onclick='signPay(<?= json_encode(['id' => $p['id'], 'payee' => $p['payee'], 'amount' => money($p['amount'])], JSON_HEX_APOS | JSON_HEX_QUOT) ?>)'>✍</button>
              <form method="post" style="display:inline" data-confirm="Reject this payment?"><input type="hidden" name="action" value="pay-reject">
                <input type="hidden" name="id" value="<?= $p['id'] ?>"><button class="btn btn-icon" title="reject">✕</button></form>
            <?php elseif ($p['status'] === 'rejected'): ?>
              <form method="post" style="display:inline" data-confirm="Delete this payment?"><input type="hidden" name="action" value="pay-del">
                <input type="hidden" name="id" value="<?= $p['id'] ?>"><button class="btn btn-icon">✕</button></form>
            <?php else: ?>
              <span class="muted" style="font-size:11px" title="locked — posted to the ledger">🔒</span>
            <?php endif; ?>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No payments yet. Request one — it will wait here until an authorized signatory signs it off.</div><?php endif; ?>
</div>

<dialog id="pay-form" class="dlg"><form method="post">
  <h2>New Payment Request</h2><input type="hidden" name="action" value="pay-new">
  <label>Payee *</label><input name="payee" required>
  <label>Purpose</label><input name="purpose" placeholder="Office rent, supplier invoice, salary advance…">
  <div class="form-row">
    <div><label>Amount *</label><input name="amount" type="number" step="any" min="0.01" required></div>
    <div><label>Method</label><select name="method"><option>bank</option><option>cash</option><option>mobile</option><option>cheque</option></select></div>
  </div>
  <label>Client (optional)</label><select name="client_id"><option value="">— none / internal —</option>
    <?php foreach ($clients as $c) echo '<option value="' . $c['id'] . '">' . e($c['name']) . '</option>'; ?>
  </select>
  <div class="form-row">
    <div><label>Pay for (debit)</label><select name="debit_account"><?= $debitOpts ?></select></div>
    <div><label>Pay from (credit)</label><select name="credit_account"><?= $creditOpts ?></select></div>
  </div>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Request payment</button></div>
</form></dialog>

<dialog id="sign-form" class="dlg"><form method="post">
  <h2 id="sign-title">Authorize Payment</h2>
  <input type="hidden" name="action" value="pay-sign"><input type="hidden" name="id" id="sign-id">
  <div class="muted" id="sign-sub" style="font-size:12.5px;margin-bottom:6px"></div>
  <div style="font-size:12px;color:var(--muted);margin-bottom:8px">
    Signing authorizes this payment and posts it to the double-entry ledger. The signature is permanent.
  </div>
  <label>Signatory name *</label><input name="signed_by" placeholder="e.g. Jane Doe, Finance Director" required>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Sign &amp; post</button></div>
</form></dialog>

<script>
function signPay(p) {
  document.getElementById('sign-title').textContent = 'Authorize Payment — ' + p.payee;
  document.getElementById('sign-sub').innerHTML = 'Amount: <strong>' + p.amount + '</strong>';
  document.getElementById('sign-id').value = p.id;
  document.getElementById('sign-form').showModal();
}
</script>

<?php require __DIR__ . '/includes/footer.php'; ?>
