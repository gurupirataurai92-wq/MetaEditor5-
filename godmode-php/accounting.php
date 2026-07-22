<?php
require_once __DIR__ . '/includes/functions.php';

if (is_post()) {
    switch (post('action')) {
        case 'account-new':
            insert('INSERT INTO accounts (name, type) VALUES (?,?)', [post('name'), post('type', 'Asset')]);
            redirect('accounting.php', 'Account added.');
        case 'journal-new':
            $debit = (int) post('debit'); $credit = (int) post('credit'); $amt = (float) post('amount');
            if ($debit === $credit) redirect('accounting.php', 'Debit and credit accounts must differ.');
            if ($amt <= 0) redirect('accounting.php', 'Amount must be positive.');
            insert('INSERT INTO journal (entry_date, memo, debit_account, credit_account, amount) VALUES (?,?,?,?,?)',
                [post('date', today()), post('memo'), $debit, $credit, $amt]);
            redirect('accounting.php', 'Entry posted.');
        case 'journal-del':
            q('DELETE FROM journal WHERE id = ?', [(int) post('id')]);
            redirect('accounting.php', 'Entry removed.');
    }
    redirect('accounting.php');
}

$pageTitle = 'Accounting';
require __DIR__ . '/includes/header.php';
$fin = financials();
$bal = account_balances();
$accts = rows('SELECT * FROM accounts ORDER BY id');
$acctName = [];
foreach ($accts as $a) { $acctName[(int) $a['id']] = $a['name']; }
$equityTotal = $fin['totalEquity'] + $fin['netIncome'];

function acct_section(string $title, array $rowsData, string $totalLabel): string
{
    $body = '';
    foreach ($rowsData as $r) {
        $body .= '<div class="report-line"><span>' . e($r['acc']['name']) . '</span><span class="amt">' . money($r['amt']) . '</span></div>';
    }
    if (!$body) $body = '<div class="muted" style="font-size:12px">—</div>';
    $tot = array_sum(array_column($rowsData, 'amt'));
    return '<div class="report-section"><h4>' . e($title) . '</h4>' . $body
         . '<div class="report-line total"><span>' . e($totalLabel) . '</span><span class="amt">' . money($tot) . '</span></div></div>';
}
$journal = rows('SELECT * FROM journal ORDER BY id DESC');
$optionTags = '';
foreach ($accts as $a) { $optionTags .= '<option value="' . $a['id'] . '">' . e($a['name'] . ' (' . $a['type'] . ')') . '</option>'; }
?>
<div class="view-head">
  <div><h1>Accounting</h1>
    <div class="sub">Double-entry ledger with live P&amp;L, balance sheet and trial balance.</div></div>
  <div class="head-actions">
    <button class="btn" onclick="document.getElementById('account-form').showModal()">+ Account</button>
    <button class="btn btn-primary" onclick="document.getElementById('journal-form').showModal()">+ Journal Entry</button>
  </div>
</div>

<div class="grid grid-3">
  <div class="card">
    <h3>Income Statement</h3>
    <?= acct_section('Income', $fin['income'], 'Total income') ?>
    <?= acct_section('Expenses', $fin['expense'], 'Total expenses') ?>
    <div class="report-line total"><span>NET INCOME</span>
      <span class="amt <?= $fin['netIncome'] >= 0 ? 'pos' : 'neg' ?>"><?= money($fin['netIncome']) ?></span></div>
  </div>
  <div class="card">
    <h3>Balance Sheet</h3>
    <?= acct_section('Assets', $fin['assets'], 'Total assets') ?>
    <?= acct_section('Liabilities', $fin['liabs'], 'Total liabilities') ?>
    <div class="report-section"><h4>Equity</h4>
      <?php foreach ($fin['equity'] as $r): ?>
        <div class="report-line"><span><?= e($r['acc']['name']) ?></span><span class="amt"><?= money($r['amt']) ?></span></div>
      <?php endforeach; ?>
      <div class="report-line"><span>Retained earnings (period)</span><span class="amt"><?= money($fin['netIncome']) ?></span></div>
      <div class="report-line total"><span>Liabilities + Equity</span><span class="amt"><?= money($fin['totalLiabs'] + $equityTotal) ?></span></div>
    </div>
    <div class="muted" style="font-size:11.5px">
      <?= abs($fin['totalAssets'] - ($fin['totalLiabs'] + $equityTotal)) < 0.005 ? '✓ Books are balanced.' : '⚠ Books do not balance — check entries.' ?>
    </div>
  </div>
  <div class="card">
    <h3>Trial Balance</h3>
    <div class="tbl-wrap"><table>
      <tr><th>Account</th><th class="num">Debit</th><th class="num">Credit</th></tr>
      <?php foreach ($accts as $a): $raw = $bal[(int) $a['id']] ?? 0; ?>
        <tr><td><?= e($a['name']) ?> <span class="muted">(<?= e($a['type']) ?>)</span></td>
          <td class="num"><?= $raw > 0 ? fnum($raw) : '' ?></td>
          <td class="num"><?= $raw < 0 ? fnum(-$raw) : '' ?></td></tr>
      <?php endforeach; ?>
    </table></div>
  </div>
</div>

<div class="card mt">
  <h3>Journal (<?= count($journal) ?> entries)</h3>
  <?php if ($journal): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Date</th><th>Memo</th><th>Debit</th><th>Credit</th><th class="num">Amount</th><th></th></tr>
      <?php foreach ($journal as $j): ?>
        <tr><td><?= e($j['entry_date']) ?></td><td><?= e($j['memo']) ?></td>
          <td><?= e($acctName[(int) $j['debit_account']] ?? '?') ?></td>
          <td><?= e($acctName[(int) $j['credit_account']] ?? '?') ?></td>
          <td class="num"><?= money($j['amount']) ?></td>
          <td><form method="post" style="display:inline" data-confirm="Delete this entry?">
            <input type="hidden" name="action" value="journal-del"><input type="hidden" name="id" value="<?= $j['id'] ?>">
            <button class="btn btn-icon">✕</button></form></td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No entries. Record your first transaction — e.g. debit Cash, credit Consulting Fees.</div><?php endif; ?>
</div>

<dialog id="account-form" class="dlg"><form method="post">
  <h2>New Account</h2><input type="hidden" name="action" value="account-new">
  <label>Account name *</label><input name="name" required>
  <label>Type</label><select name="type"><?php foreach (['Asset','Liability','Equity','Income','Expense'] as $t) echo "<option>$t</option>"; ?></select>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<dialog id="journal-form" class="dlg"><form method="post">
  <h2>New Journal Entry</h2><input type="hidden" name="action" value="journal-new">
  <div class="form-row">
    <div><label>Date</label><input name="date" type="date" value="<?= today() ?>" required></div>
    <div><label>Amount *</label><input name="amount" type="number" step="any" min="0.01" required></div>
  </div>
  <label>Debit account</label><select name="debit"><?= $optionTags ?></select>
  <label>Credit account</label><select name="credit"><?= $optionTags ?></select>
  <label>Memo</label><input name="memo" placeholder="Invoice #12 — consulting retainer">
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Post</button></div>
</form></dialog>

<?php require __DIR__ . '/includes/footer.php'; ?>
