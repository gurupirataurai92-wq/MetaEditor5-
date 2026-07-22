<?php
require_once __DIR__ . '/includes/functions.php';

if (is_post()) {
    switch (post('action')) {
        case 'inv-new':
            $items = [];
            foreach (explode("\n", post('lines')) as $line) {
                $parts = array_map('trim', explode('|', $line));
                if (($parts[0] ?? '') === '') continue;
                $items[] = [$parts[0], (float) ($parts[1] ?? 1) ?: 1, (float) ($parts[2] ?? 0)];
            }
            if (!$items) redirect('invoicing.php', 'Add at least one line item.');
            $id = insert('INSERT INTO invoices (number, client_id, issue_date, due_date, status) VALUES (?,?,?,?,?)',
                [next_invoice_number(), (int) post('client_id'), post('date', today()), post('due_date', today()), 'draft']);
            foreach ($items as $it) {
                insert('INSERT INTO invoice_items (invoice_id, description, qty, price) VALUES (?,?,?,?)',
                    [$id, $it[0], $it[1], $it[2]]);
            }
            redirect('invoicing.php', 'Invoice drafted.');
        case 'inv-send':
            q("UPDATE invoices SET status = 'sent' WHERE id = ?", [(int) post('id')]);
            redirect('invoicing.php', 'Invoice marked as sent.');
        case 'inv-paid':
            $id = (int) post('id');
            q("UPDATE invoices SET status = 'paid', paid_date = ? WHERE id = ?", [today(), $id]);
            $inv = one('SELECT * FROM invoices WHERE id = ?', [$id]);
            $cash = scalar("SELECT id FROM accounts WHERE name = 'Cash & Bank' LIMIT 1")
                 ?: scalar("SELECT id FROM accounts WHERE type = 'Asset' ORDER BY id LIMIT 1");
            $fees = scalar("SELECT id FROM accounts WHERE name = 'Consulting Fees' LIMIT 1")
                 ?: scalar("SELECT id FROM accounts WHERE type = 'Income' ORDER BY id LIMIT 1");
            if ($cash && $fees) {
                insert('INSERT INTO journal (entry_date, memo, debit_account, credit_account, amount) VALUES (?,?,?,?,?)',
                    [today(), $inv['number'] . ' — ' . client_name((int) $inv['client_id']), (int) $cash, (int) $fees, invoice_total($id)]);
                redirect('invoicing.php', $inv['number'] . ' paid — posted to the books.');
            }
            redirect('invoicing.php', 'Invoice marked paid.');
        case 'inv-del':
            q('DELETE FROM invoices WHERE id = ?', [(int) post('id')]);
            redirect('invoicing.php', 'Invoice removed.');
    }
    redirect('invoicing.php');
}

$pageTitle = 'Invoicing';
require __DIR__ . '/includes/header.php';
$s = invoice_stats();
$invoices = rows('SELECT * FROM invoices ORDER BY id DESC');
$clients = rows('SELECT id, name FROM clients ORDER BY name');
$due30 = date('Y-m-d', strtotime('+30 days'));
?>
<div class="view-head">
  <div><h1>Invoicing &amp; Billing</h1>
    <div class="sub">Issue invoices, chase receivables — marking paid posts the books automatically.</div></div>
  <div class="head-actions">
    <button class="btn btn-primary" onclick="document.getElementById('inv-form').showModal()" <?= $clients ? '' : 'disabled' ?>>+ Invoice</button>
  </div>
</div>

<div class="grid grid-4">
  <div class="stat"><div class="label">Invoices</div><div class="value"><?= count($invoices) ?></div></div>
  <div class="stat accent"><div class="label">Outstanding</div><div class="value"><?= money($s['outstanding']) ?></div></div>
  <div class="stat <?= $s['overdueCount'] ? 'bad' : 'good' ?>"><div class="label">Overdue</div><div class="value"><?= money($s['overdue']) ?></div>
    <div class="hint"><?= $s['overdueCount'] ?> invoice(s)</div></div>
  <div class="stat good"><div class="label">Collected</div><div class="value"><?= money($s['collected']) ?></div></div>
</div>

<div class="card mt">
  <h3>Invoices</h3>
  <?php if ($invoices): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Number</th><th>Client</th><th>Issued</th><th>Due</th><th class="num">Total</th><th>Status</th><th></th></tr>
      <?php foreach ($invoices as $i): ?>
        <tr><td class="mono"><?= e($i['number']) ?></td><td><?= e(client_name((int) $i['client_id'])) ?></td>
          <td><?= e($i['issue_date']) ?></td><td><?= e($i['due_date']) ?></td>
          <td class="num"><?= money(invoice_total((int) $i['id'])) ?></td>
          <td><?php echo $i['status'] === 'paid' ? badge('paid', 'b-green')
                    : (invoice_overdue($i) ? badge('overdue', 'b-red')
                    : ($i['status'] === 'sent' ? badge('sent', 'b-blue') : badge('draft', 'b-grey'))); ?></td>
          <td style="white-space:nowrap">
            <a class="btn btn-icon" href="invoice.php?id=<?= $i['id'] ?>" title="view / print">▤</a>
            <?php if ($i['status'] === 'draft'): ?>
            <form method="post" style="display:inline"><input type="hidden" name="action" value="inv-send">
              <input type="hidden" name="id" value="<?= $i['id'] ?>"><button class="btn btn-icon" title="mark sent">→</button></form>
            <?php endif; ?>
            <?php if ($i['status'] === 'sent'): ?>
            <form method="post" style="display:inline"><input type="hidden" name="action" value="inv-paid">
              <input type="hidden" name="id" value="<?= $i['id'] ?>"><button class="btn btn-icon" title="mark paid + post to books">✓</button></form>
            <?php endif; ?>
            <form method="post" style="display:inline" data-confirm="Delete this invoice?"><input type="hidden" name="action" value="inv-del">
              <input type="hidden" name="id" value="<?= $i['id'] ?>"><button class="btn btn-icon">✕</button></form>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No invoices yet. Bill an engagement — one line per item: description | qty | unit price.</div><?php endif; ?>
</div>

<dialog id="inv-form" class="dlg"><form method="post">
  <h2>New Invoice — <?= e(next_invoice_number()) ?></h2><input type="hidden" name="action" value="inv-new">
  <label>Client *</label><select name="client_id" required>
    <?php foreach ($clients as $c) echo '<option value="' . $c['id'] . '">' . e($c['name']) . '</option>'; ?>
  </select>
  <div class="form-row">
    <div><label>Issue date</label><input name="date" type="date" value="<?= today() ?>" required></div>
    <div><label>Due date</label><input name="due_date" type="date" value="<?= $due30 ?>" required></div>
  </div>
  <label>Line items — one per line: description | qty | unit price</label>
  <textarea name="lines" rows="5" placeholder="Monthly retainer | 1 | 2500&#10;Audit fieldwork days | 3 | 400" required></textarea>
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Create Invoice</button></div>
</form></dialog>

<?php require __DIR__ . '/includes/footer.php'; ?>
