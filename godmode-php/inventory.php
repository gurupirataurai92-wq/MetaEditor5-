<?php
require_once __DIR__ . '/includes/guard.php';

if (is_post()) {
    switch (post('action')) {
        case 'item-new':
            insert('INSERT INTO inventory_items (sku, name, category, unit, quantity, unit_cost, reorder_level, updated_at)
                    VALUES (?,?,?,?,?,?,?,?)',
                [post('sku'), post('name'), post('category'), post('unit', 'unit'),
                 (float) post('quantity'), (float) post('unit_cost'), (float) post('reorder_level'), today()]);
            redirect('inventory.php', 'Item added.');
        case 'stock-move':
            $it = one('SELECT * FROM inventory_items WHERE id = ?', [(int) post('id')]);
            if ($it) {
                $type = post('move_type', 'in');
                $qty = (float) post('qty');
                if ($qty > 0) {
                    $current = (float) $it['quantity'];
                    if ($type === 'in')       $new = $current + $qty;
                    elseif ($type === 'out')  $new = max(0, $current - $qty);
                    else                      $new = $qty;                 // set exact
                    q('UPDATE inventory_items SET quantity = ?, updated_at = ? WHERE id = ?', [$new, today(), $it['id']]);
                    insert('INSERT INTO inventory_moves (item_id, move_type, qty, note, moved_at) VALUES (?,?,?,?,?)',
                        [$it['id'], $type, $qty, post('note'), today()]);
                    redirect('inventory.php', 'Stock updated: ' . $it['name'] . ' → ' . fnum($new) . ' ' . $it['unit']);
                }
            }
            redirect('inventory.php');
        case 'item-del':
            q('DELETE FROM inventory_items WHERE id = ?', [(int) post('id')]);
            redirect('inventory.php', 'Item removed.');
    }
    redirect('inventory.php');
}

$pageTitle = 'Inventory';
require __DIR__ . '/includes/header.php';
$stats = inventory_stats();
$items = rows('SELECT * FROM inventory_items ORDER BY name');
$moves = rows('SELECT m.*, i.name AS item_name, i.unit AS unit FROM inventory_moves m
               JOIN inventory_items i ON i.id = m.item_id ORDER BY m.id DESC LIMIT 12');
?>
<div class="view-head">
  <div><h1>Inventory</h1>
    <div class="sub">Stock levels with automatic reorder alerts and a full movement log.</div></div>
  <div class="head-actions"><button class="btn btn-primary" onclick="document.getElementById('item-form').showModal()">+ Item</button></div>
</div>

<div class="grid grid-4">
  <div class="stat"><div class="label">Items</div><div class="value"><?= $stats['count'] ?></div></div>
  <div class="stat accent"><div class="label">Stock Value</div><div class="value"><?= money($stats['value']) ?></div></div>
  <div class="stat <?= $stats['low'] ? 'warn' : 'good' ?>"><div class="label">Low Stock</div><div class="value"><?= $stats['low'] ?></div>
    <div class="hint">at / below reorder level</div></div>
  <div class="stat <?= $stats['out'] ? 'bad' : 'good' ?>"><div class="label">Out of Stock</div><div class="value"><?= $stats['out'] ?></div></div>
</div>

<div class="card mt">
  <h3>Stock Register</h3>
  <?php if ($items): ?>
    <div class="tbl-wrap"><table>
      <tr><th>Item</th><th>SKU</th><th>Category</th><th class="num">On hand</th><th class="num">Unit cost</th>
        <th class="num">Value</th><th class="num">Reorder</th><th>Status</th><th></th></tr>
      <?php foreach ($items as $it): [$label, $cls] = stock_status($it);
        $val = (float) $it['quantity'] * (float) $it['unit_cost']; ?>
        <tr><td><strong><?= e($it['name']) ?></strong></td><td class="mono"><?= e($it['sku'] ?: '—') ?></td>
          <td><?= e($it['category'] ?: '—') ?></td>
          <td class="num"><?= fnum($it['quantity']) ?> <span class="muted"><?= e($it['unit']) ?></span></td>
          <td class="num"><?= money($it['unit_cost']) ?></td>
          <td class="num"><?= money($val) ?></td>
          <td class="num"><?= fnum($it['reorder_level']) ?></td>
          <td><?= badge($label, $cls) ?></td>
          <td style="white-space:nowrap">
            <button class="btn btn-icon" title="stock in"
              onclick='stockMove(<?= json_encode(['id' => $it['id'], 'name' => $it['name'], 'type' => 'in', 'unit' => $it['unit']], JSON_HEX_APOS | JSON_HEX_QUOT) ?>)'>＋</button>
            <button class="btn btn-icon" title="stock out"
              onclick='stockMove(<?= json_encode(['id' => $it['id'], 'name' => $it['name'], 'type' => 'out', 'unit' => $it['unit']], JSON_HEX_APOS | JSON_HEX_QUOT) ?>)'>－</button>
            <form method="post" style="display:inline" data-confirm="Delete this item?"><input type="hidden" name="action" value="item-del">
              <input type="hidden" name="id" value="<?= $it['id'] ?>"><button class="btn btn-icon">✕</button></form>
          </td></tr>
      <?php endforeach; ?>
    </table></div>
  <?php else: ?><div class="empty">No items yet. Add stock to start tracking levels and reorder alerts.</div><?php endif; ?>
</div>

<?php if ($moves): ?>
<div class="card mt">
  <h3>Recent Movements</h3>
  <div class="tbl-wrap"><table>
    <tr><th>Date</th><th>Item</th><th>Type</th><th class="num">Qty</th><th>Note</th></tr>
    <?php foreach ($moves as $m): ?>
      <tr><td><?= e($m['moved_at']) ?></td><td><?= e($m['item_name']) ?></td>
        <td><?php echo $m['move_type'] === 'in' ? badge('stock in', 'b-green')
                  : ($m['move_type'] === 'out' ? badge('stock out', 'b-amber') : badge('set', 'b-blue')); ?></td>
        <td class="num"><?= fnum($m['qty']) ?> <span class="muted"><?= e($m['unit']) ?></span></td>
        <td><?= e($m['note'] ?: '—') ?></td></tr>
    <?php endforeach; ?>
  </table></div>
</div>
<?php endif; ?>

<dialog id="item-form" class="dlg"><form method="post">
  <h2>New Item</h2><input type="hidden" name="action" value="item-new">
  <label>Item name *</label><input name="name" required>
  <div class="form-row">
    <div><label>SKU</label><input name="sku"></div>
    <div><label>Category</label><input name="category"></div>
  </div>
  <div class="form-row-3">
    <div><label>Opening qty</label><input name="quantity" type="number" step="any" min="0" value="0"></div>
    <div><label>Unit</label><input name="unit" value="unit"></div>
    <div><label>Reorder level</label><input name="reorder_level" type="number" step="any" min="0" value="0"></div>
  </div>
  <label>Unit cost</label><input name="unit_cost" type="number" step="any" min="0" value="0">
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Save</button></div>
</form></dialog>

<dialog id="move-form" class="dlg"><form method="post">
  <h2 id="move-title">Stock movement</h2>
  <input type="hidden" name="action" value="stock-move"><input type="hidden" name="id" id="move-id">
  <input type="hidden" name="move_type" id="move-type">
  <label id="move-label">Quantity</label><input name="qty" id="move-qty" type="number" step="any" min="0.01" required>
  <label>Note (supplier, reason…)</label><input name="note">
  <div class="modal-actions"><button type="button" class="btn" onclick="this.closest('dialog').close()">Cancel</button>
    <button class="btn btn-primary">Apply</button></div>
</form></dialog>

<script>
function stockMove(m) {
  document.getElementById('move-title').textContent = (m.type === 'in' ? 'Stock In — ' : 'Stock Out — ') + m.name;
  document.getElementById('move-label').textContent = (m.type === 'in' ? 'Quantity received' : 'Quantity issued') + ' (' + m.unit + ')';
  document.getElementById('move-id').value = m.id;
  document.getElementById('move-type').value = m.type;
  document.getElementById('move-qty').value = '';
  document.getElementById('move-form').showModal();
}
</script>

<?php require __DIR__ . '/includes/footer.php'; ?>
