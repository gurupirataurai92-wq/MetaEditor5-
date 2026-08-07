<?php
require_once __DIR__ . '/includes/guard.php';
$id = (int) getp('id');
$inv = one('SELECT * FROM invoices WHERE id = ?', [$id]);
if (!$inv) { http_response_code(404); echo 'Invoice not found.'; exit; }
$items = invoice_items($id);
$total = invoice_total($id);
$pageTitle = 'Invoice ' . $inv['number'];
require __DIR__ . '/includes/header.php';
?>
<div class="view-head no-print">
  <div><h1>Invoice <?= e($inv['number']) ?></h1>
    <div class="sub"><a href="invoicing.php">← back to invoices</a></div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="window.print()">Print / PDF</button></div>
</div>

<div class="paper">
  <div class="paper-head">
    <div><h1>INVOICE</h1><div class="muted"><?= e($inv['number']) ?></div></div>
    <div style="text-align:right">
      <div><strong>Billed to:</strong> <?= e(client_name((int) $inv['client_id'])) ?></div>
      <div class="muted">Issued <?= e($inv['issue_date']) ?> · Due <?= e($inv['due_date']) ?></div>
      <div style="margin-top:6px">
        <?php echo $inv['status'] === 'paid' ? badge('PAID', 'b-green')
              : (invoice_overdue($inv) ? badge('OVERDUE', 'b-red') : badge(strtoupper($inv['status']), 'b-grey')); ?>
      </div>
    </div>
  </div>
  <table>
    <tr><th>Description</th><th class="num">Qty</th><th class="num">Unit price</th><th class="num">Amount</th></tr>
    <?php foreach ($items as $it): ?>
      <tr><td><?= e($it['description']) ?></td><td class="num"><?= fnum($it['qty']) ?></td>
        <td class="num"><?= money($it['price']) ?></td><td class="num"><?= money((float) $it['qty'] * (float) $it['price']) ?></td></tr>
    <?php endforeach; ?>
  </table>
  <div class="paper-total">Total due: <?= money($total) ?></div>
</div>

<?php require __DIR__ . '/includes/footer.php'; ?>
